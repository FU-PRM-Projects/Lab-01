use byteorder::{LittleEndian, ReadBytesExt, WriteBytesExt};
use itertools::Itertools;
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::Path;
use std::sync::RwLock;

const MAGIC: &[u8; 4] = b"TVEC";
const CURRENT_VERSION: u32 = 1;

#[derive(Clone, Debug, PartialEq)]
pub struct RustSearchResult {
    pub vector_id: u64,
    pub score: f32,
}

struct IndexInner {
    dim: usize,
    bit_width: usize,
    vectors: HashMap<u64, Vec<f32>>,
}

pub struct NativeVectorIndex {
    inner: RwLock<IndexInner>,
}

impl NativeVectorIndex {
    pub fn new(dim: usize, bit_width: usize) -> Self {
        Self {
            inner: RwLock::new(IndexInner {
                dim,
                bit_width,
                vectors: HashMap::new(),
            }),
        }
    }

    pub fn load(path: String) -> Result<Self, String> {
        let file = File::open(Path::new(&path))
            .map_err(|e| format!("Failed to open index file at {path}: {e}"))?;
        let mut reader = BufReader::new(file);

        let mut magic = [0u8; 4];
        reader
            .read_exact(&mut magic)
            .map_err(|e| format!("Failed to read magic: {e}"))?;
        if &magic != MAGIC {
            return Err(format!(
                "Invalid TVEC magic bytes: {:?}",
                String::from_utf8_lossy(&magic)
            ));
        }

        let version = reader
            .read_u32::<LittleEndian>()
            .map_err(|e| format!("Failed to read version: {e}"))?;
        if version != CURRENT_VERSION {
            return Err(format!("Unsupported TVEC version: {version}"));
        }

        let dim = reader
            .read_u64::<LittleEndian>()
            .map_err(|e| format!("Failed to read dim: {e}"))? as usize;
        let bit_width = reader
            .read_u64::<LittleEndian>()
            .map_err(|e| format!("Failed to read bit_width: {e}"))? as usize;
        let count = reader
            .read_u64::<LittleEndian>()
            .map_err(|e| format!("Failed to read count: {e}"))? as usize;

        let expected_size = (dim as u64).checked_mul(4).and_then(|size| size.checked_add(8))
            .and_then(|size| size.checked_mul(count as u64)).and_then(|size| size.checked_add(32));
        let file_size = reader.get_ref().metadata().map_err(|e| e.to_string())?.len();
        if dim == 0 || expected_size != Some(file_size) {
            return Err("Invalid vector index size or dimensions".into());
        }
        let mut vectors = HashMap::with_capacity(count);
        for _ in 0..count {
            let id = reader
                .read_u64::<LittleEndian>()
                .map_err(|e| format!("Failed to read vector id: {e}"))?;
            let mut vec = vec![0.0f32; dim];
            for val in vec.iter_mut() {
                *val = reader
                    .read_f32::<LittleEndian>()
                    .map_err(|e| format!("Failed to read vector float: {e}"))?;
            }
            validate_vector(&vec)?;
            if vectors.insert(id, vec).is_some() { return Err(format!("Duplicate vector ID: {id}")); }
        }

        Ok(Self {
            inner: RwLock::new(IndexInner {
                dim,
                bit_width,
                vectors,
            }),
        })
    }

    pub fn write(&self, path: String) -> Result<(), String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        let file = File::create(Path::new(&path))
            .map_err(|e| format!("Failed to create index file at {path}: {e}"))?;
        let mut writer = BufWriter::new(file);

        writer
            .write_all(MAGIC)
            .map_err(|e| format!("Failed to write magic: {e}"))?;
        writer
            .write_u32::<LittleEndian>(CURRENT_VERSION)
            .map_err(|e| format!("Failed to write version: {e}"))?;
        writer
            .write_u64::<LittleEndian>(inner.dim as u64)
            .map_err(|e| format!("Failed to write dim: {e}"))?;
        writer
            .write_u64::<LittleEndian>(inner.bit_width as u64)
            .map_err(|e| format!("Failed to write bit_width: {e}"))?;
        writer
            .write_u64::<LittleEndian>(inner.vectors.len() as u64)
            .map_err(|e| format!("Failed to write count: {e}"))?;

        for (&id, vec) in &inner.vectors {
            writer
                .write_u64::<LittleEndian>(id)
                .map_err(|e| format!("Failed to write vector id: {e}"))?;
            for &val in vec {
                writer
                    .write_f32::<LittleEndian>(val)
                    .map_err(|e| format!("Failed to write vector value: {e}"))?;
            }
        }

        writer
            .flush()
            .map_err(|e| format!("Failed to flush index file: {e}"))?;
        Ok(())
    }

    pub fn add_batch(
        &self,
        ids: Vec<u64>,
        vectors: Vec<f32>,
        dim: usize,
    ) -> Result<(), String> {
        let mut inner = self.inner.write().map_err(|e| e.to_string())?;
        if inner.dim == 0 {
            inner.dim = dim;
        } else if inner.dim != dim {
            return Err(format!(
                "Dimension mismatch: expected {}, got {}",
                inner.dim, dim
            ));
        }

        if ids.is_empty() {
            return Ok(());
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

        if dim == 0 { return Err("Vector dimensions must be positive".into()); }
        let mut seen = HashSet::new();
        for &id in &ids {
            if inner.vectors.contains_key(&id) || !seen.insert(id) {
                return Err(format!("Duplicate vector ID: {id}"));
            }
        }
        for vector in vectors.chunks_exact(dim) { validate_vector(vector)?; }

        for (i, &id) in ids.iter().enumerate() {
            let start = i * dim;
            let end = start + dim;
            let vec_slice = vectors[start..end].to_vec();
            inner.vectors.insert(id, vec_slice);
        }

        Ok(())
    }

    pub fn search(
        &self,
        query: Vec<f32>,
        k: usize,
        allowlist: Option<Vec<u64>>,
    ) -> Result<Vec<RustSearchResult>, String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        if inner.vectors.is_empty() || inner.dim == 0 || k == 0 {
            return Ok(Vec::new());
        }

        if query.len() != inner.dim {
            return Err(format!(
                "Query dimension mismatch: expected {}, got {}",
                inner.dim,
                query.len()
            ));
        }

        let allow_set: Option<HashSet<u64>> = allowlist.map(|list| list.into_iter().collect());

        validate_vector(&query)?;
        let q_norm = norm(&query);
        Ok(inner.vectors.iter()
            .filter(|(id, _)| allow_set.as_ref().is_none_or(|allowed| allowed.contains(id)))
            .map(|(&id, vector)| {
                let dot: f64 = query.iter().zip(vector).map(|(&q, &v)| f64::from(q) * f64::from(v)).sum();
                RustSearchResult { vector_id: id, score: (dot / (q_norm * norm(vector))) as f32 }
            })
            .k_smallest_by(k, |a, b| b.score.total_cmp(&a.score).then(a.vector_id.cmp(&b.vector_id)))
            .collect())
    }

    pub fn remove(&self, id: u64) -> Result<bool, String> {
        let mut inner = self.inner.write().map_err(|e| e.to_string())?;
        Ok(inner.vectors.remove(&id).is_some())
    }

    pub fn len(&self) -> Result<usize, String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        Ok(inner.vectors.len())
    }

    pub fn dim(&self) -> Result<usize, String> {
        let inner = self.inner.read().map_err(|e| e.to_string())?;
        Ok(inner.dim)
    }


}

fn norm(vector: &[f32]) -> f64 {
    vector.iter().map(|&value| f64::from(value).powi(2)).sum::<f64>().sqrt()
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

    #[test]
    fn test_turbovec_crud_and_search() {
        let index = NativeVectorIndex::new(3, 4);
        assert_eq!(index.len().unwrap(), 0);
        assert_eq!(index.dim().unwrap(), 3);

        let ids = vec![1, 2, 3];
        // 3 vectors of dim 3
        let vectors = vec![
            1.0, 0.0, 0.0, // id 1: aligned with x
            0.0, 1.0, 0.0, // id 2: aligned with y
            0.7071, 0.7071, 0.0, // id 3: 45 degrees between x and y
        ];
        index.add_batch(ids, vectors, 3).unwrap();
        assert_eq!(index.len().unwrap(), 3);

        // Search near x axis
        let query = vec![1.0, 0.0, 0.0];
        let results = index.search(query, 2, None).unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].vector_id, 1);
        assert!((results[0].score - 1.0).abs() < 1e-4);
        assert_eq!(results[1].vector_id, 3);
        assert!((results[1].score - 0.7071).abs() < 1e-3);

        // Test allowlist filter
        let filtered = index
            .search(vec![1.0, 0.0, 0.0], 5, Some(vec![2, 3]))
            .unwrap();
        assert_eq!(filtered.len(), 2);
        assert_eq!(filtered[0].vector_id, 3);
        assert_eq!(filtered[1].vector_id, 2);

        // Test remove
        assert!(index.remove(1).unwrap());
        assert!(!index.remove(99).unwrap());
        assert_eq!(index.len().unwrap(), 2);
    }

    #[test]
    fn test_turbovec_file_persistence() {
        let temp_dir = std::env::temp_dir();
        let test_path = temp_dir.join("test_index.tvec");
        let path_str = test_path.to_str().unwrap().to_string();

        let index = NativeVectorIndex::new(2, 8);
        let ids = vec![101, 102];
        let vectors = vec![0.6, 0.8, 1.0, 0.0];
        index.add_batch(ids, vectors, 2).unwrap();
        index.write(path_str.clone()).unwrap();

        // Load back
        let loaded = NativeVectorIndex::load(path_str.clone()).unwrap();
        assert_eq!(loaded.len().unwrap(), 2);
        assert_eq!(loaded.dim().unwrap(), 2);

        let search_res = loaded.search(vec![1.0, 0.0], 1, None).unwrap();
        assert_eq!(search_res.len(), 1);
        assert_eq!(search_res[0].vector_id, 102);
        assert!((search_res[0].score - 1.0).abs() < 1e-4);

        let _ = fs::remove_file(test_path);
    }
}
