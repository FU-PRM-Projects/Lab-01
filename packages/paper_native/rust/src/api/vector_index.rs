use std::collections::HashSet;
use std::sync::RwLock;
use turbovec::IdMapIndex;

#[derive(Clone, Debug, PartialEq)]
pub struct RustSearchResult {
    pub vector_id: u64,
    pub score: f32,
}

pub struct NativeVectorIndex {
    inner: RwLock<IdMapIndex>,
}

impl NativeVectorIndex {
    /// A `dim` of zero defers the dimension until the first `add_batch`.
    pub fn new(dim: usize, bit_width: usize) -> Result<Self, String> {
        let index = if dim == 0 {
            IdMapIndex::new_lazy(bit_width)
        } else {
            IdMapIndex::new(dim, bit_width)
        }
        .map_err(|e| format!("Failed to construct vector index: {e}"))?;

        Ok(Self {
            inner: RwLock::new(index),
        })
    }

    pub fn load(path: String) -> Result<Self, String> {
        let index = IdMapIndex::load(&path)
            .map_err(|e| format!("Failed to load index file at {path}: {e}"))?;
        Ok(Self {
            inner: RwLock::new(index),
        })
    }

    pub fn write(&self, path: String) -> Result<(), String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        inner
            .write(&path)
            .map_err(|e| format!("Failed to write index file at {path}: {e}"))
    }

    pub fn add_batch(&self, ids: Vec<u64>, vectors: Vec<f32>, dim: usize) -> Result<(), String> {
        if ids.is_empty() {
            return Ok(());
        }
        if dim == 0 {
            return Err("Vector dimensions must be positive".into());
        }

        let mut inner = self.inner.write().map_err(|e| e.to_string())?;
        if let Some(existing) = inner.dim_opt() {
            if existing != dim {
                return Err(format!(
                    "Dimension mismatch: expected {existing}, got {dim}"
                ));
            }
        }

        let count = ids.len();
        if vectors.len() != count * dim {
            return Err(format!(
                "Vector buffer size mismatch: expected {} floats ({}x{}), got {}",
                count * dim,
                count,
                dim,
                vectors.len()
            ));
        }

        let mut seen = HashSet::new();
        for &id in &ids {
            if inner.contains(id) || !seen.insert(id) {
                return Err(format!("Duplicate vector ID: {id}"));
            }
        }
        for vector in vectors.chunks_exact(dim) {
            validate_vector(vector)?;
        }

        inner
            .add_with_ids_2d(&vectors, dim, &ids)
            .map_err(|e| format!("Failed to add vectors: {e}"))
    }

    pub fn search(
        &self,
        query: Vec<f32>,
        k: usize,
        allowlist: Option<Vec<u64>>,
    ) -> Result<Vec<RustSearchResult>, String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        if inner.is_empty() || k == 0 {
            return Ok(Vec::new());
        }

        let dim = inner.dim_opt().unwrap_or(0);
        if query.len() != dim {
            return Err(format!(
                "Query dimension mismatch: expected {dim}, got {}",
                query.len()
            ));
        }
        validate_vector(&query)?;

        let results = inner
            .try_search_with_allowlist(&query, k, allowlist.as_deref())
            .map_err(|e| format!("Search failed: {e}"))?;

        if results.nq == 0 {
            return Ok(Vec::new());
        }

        Ok(results
            .ids_for_query(0)
            .iter()
            .zip(results.scores_for_query(0))
            .map(|(&vector_id, &score)| RustSearchResult { vector_id, score })
            .collect())
    }

    pub fn remove(&self, id: u64) -> Result<bool, String> {
        let mut inner = self.inner.write().map_err(|e| e.to_string())?;
        Ok(inner.remove(id))
    }

    pub fn len(&self) -> Result<usize, String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        Ok(inner.len())
    }

    pub fn dim(&self) -> Result<usize, String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        Ok(inner.dim_opt().unwrap_or(0))
    }
}

fn norm(vector: &[f32]) -> f64 {
    vector
        .iter()
        .map(|&value| f64::from(value).powi(2))
        .sum::<f64>()
        .sqrt()
}

fn validate_vector(vector: &[f32]) -> Result<(), String> {
    if vector.is_empty() || vector.iter().any(|v| !v.is_finite()) || norm(vector) == 0.0 {
        return Err("Expected a finite non-zero vector".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    const DIM: usize = 128;

    /// Deterministic pseudo-random unit-ish vectors. Quantized search needs
    /// realistic dimensionality to be meaningful, so the fixtures are
    /// generated rather than hand-written.
    fn synth(n: usize, seed: u64) -> Vec<f32> {
        let mut state = seed | 1;
        (0..n * DIM)
            .map(|_| {
                state = state
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                ((state >> 33) as f32 / (1u64 << 31) as f32) - 1.0
            })
            .collect()
    }

    fn row(vectors: &[f32], i: usize) -> Vec<f32> {
        vectors[i * DIM..(i + 1) * DIM].to_vec()
    }

    #[test]
    fn test_turbovec_crud_and_search() {
        let index = NativeVectorIndex::new(DIM, 4).unwrap();
        assert_eq!(index.len().unwrap(), 0);
        assert_eq!(index.dim().unwrap(), DIM);

        let ids: Vec<u64> = (1..=8).collect();
        let vectors = synth(8, 0xD1536);
        index.add_batch(ids, vectors.clone(), DIM).unwrap();
        assert_eq!(index.len().unwrap(), 8);

        // Querying with a stored vector must rank that vector first.
        let results = index.search(row(&vectors, 2), 3, None).unwrap();
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].vector_id, 3);
        // Scores are descending within a row.
        assert!(results[0].score >= results[1].score);
        assert!(results[1].score >= results[2].score);

        // The allowlist restricts the candidate set.
        let filtered = index.search(row(&vectors, 2), 5, Some(vec![5, 7])).unwrap();
        assert_eq!(filtered.len(), 2);
        let returned: HashSet<u64> = filtered.iter().map(|r| r.vector_id).collect();
        assert_eq!(returned, HashSet::from([5, 7]));

        assert!(index.remove(1).unwrap());
        assert!(!index.remove(99).unwrap());
        assert_eq!(index.len().unwrap(), 7);
        let after_removal = index.search(row(&vectors, 0), 7, None).unwrap();
        assert!(after_removal.iter().all(|r| r.vector_id != 1));
    }

    #[test]
    fn test_turbovec_file_persistence() {
        let test_path = std::env::temp_dir().join("test_index.tv");
        let path_str = test_path.to_str().unwrap().to_string();

        let index = NativeVectorIndex::new(DIM, 4).unwrap();
        let ids = vec![101, 102, 103];
        let vectors = synth(3, 0xA55E3);
        index.add_batch(ids, vectors.clone(), DIM).unwrap();
        index.write(path_str.clone()).unwrap();

        let loaded = NativeVectorIndex::load(path_str.clone()).unwrap();
        assert_eq!(loaded.len().unwrap(), 3);
        assert_eq!(loaded.dim().unwrap(), DIM);

        let search_res = loaded.search(row(&vectors, 1), 1, None).unwrap();
        assert_eq!(search_res.len(), 1);
        assert_eq!(search_res[0].vector_id, 102);

        let _ = fs::remove_file(test_path);
    }

    #[test]
    fn test_lazy_dimension_is_locked_by_first_add() {
        let index = NativeVectorIndex::new(0, 4).unwrap();
        assert_eq!(index.dim().unwrap(), 0);

        index.add_batch(vec![1], synth(1, 7), DIM).unwrap();
        assert_eq!(index.dim().unwrap(), DIM);

        let err = index
            .add_batch(vec![2], vec![1.0; DIM * 2], DIM * 2)
            .unwrap_err();
        assert!(err.contains("Dimension mismatch"), "{err}");
    }

    #[test]
    fn test_turbovec_rejects_bad_input() {
        let index = NativeVectorIndex::new(DIM, 4).unwrap();
        let vectors = synth(2, 11);
        index.add_batch(vec![1, 2], vectors, DIM).unwrap();

        let duplicate = index.add_batch(vec![2], synth(1, 12), DIM).unwrap_err();
        assert!(duplicate.contains("Duplicate vector ID"), "{duplicate}");

        let in_batch = index.add_batch(vec![9, 9], synth(2, 13), DIM).unwrap_err();
        assert!(in_batch.contains("Duplicate vector ID"), "{in_batch}");

        let short = index
            .add_batch(vec![3], vec![0.5; DIM - 1], DIM)
            .unwrap_err();
        assert!(short.contains("Vector buffer size mismatch"), "{short}");

        let zero = index.add_batch(vec![4], vec![0.0; DIM], DIM).unwrap_err();
        assert!(zero.contains("finite non-zero"), "{zero}");

        let query_dim = index.search(vec![1.0; DIM + 1], 1, None).unwrap_err();
        assert!(
            query_dim.contains("Query dimension mismatch"),
            "{query_dim}"
        );

        // An unsupported bit width is rejected at construction.
        assert!(NativeVectorIndex::new(DIM, 8).is_err());
    }

    #[test]
    fn test_empty_and_zero_k_searches_are_empty() {
        let index = NativeVectorIndex::new(DIM, 4).unwrap();
        assert!(index.search(vec![1.0; DIM], 5, None).unwrap().is_empty());

        index.add_batch(vec![1], synth(1, 17), DIM).unwrap();
        assert!(index.search(vec![1.0; DIM], 0, None).unwrap().is_empty());
    }
}
