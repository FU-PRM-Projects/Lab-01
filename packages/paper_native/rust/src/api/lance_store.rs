//! LanceDB-backed chunk store.
//!
//! One table per collection. Unlike the previous TVEC index, the vector is
//! stored alongside the chunk's metadata and text, so a search returns
//! everything retrieval needs and the caller keeps no vector-id bookkeeping.

use std::collections::HashSet;
use std::sync::{Arc, OnceLock};

use arrow_array::builder::{FixedSizeListBuilder, Float32Builder, Int32Builder, StringBuilder};
use arrow_array::{Array, Float32Array, Int32Array, RecordBatch, StringArray};
use arrow_schema::{DataType, Field, Schema, SchemaRef};
use futures::TryStreamExt;
use lancedb::query::{ExecutableQuery, QueryBase, Select};
use lancedb::table::OptimizeAction;
use lancedb::{DistanceType, Table};

const TABLE_NAME: &str = "chunks";

/// Prefix the Dart wrapper matches on to rethrow its own profile-mismatch error.
const DIM_MISMATCH: &str = "DIM_MISMATCH";

/// lancedb is tokio-only and needs the IO and time drivers.
///
/// flutter_rust_bridge dispatches these synchronous calls on its own worker
/// pool (never a tokio worker), so blocking here cannot deadlock and never
/// stalls the Dart isolate. Owning the runtime explicitly also keeps the store
/// independent of which tokio features happen to be unified into the build.
static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn rt() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("lance")
            .build()
            .expect("failed to start the tokio runtime")
    })
}

/// One indexed chunk. Mirrors the persisted columns, minus the vector.
#[derive(Clone, Debug, PartialEq)]
pub struct RustChunkRow {
    pub chunk_id: String,
    pub doc_id: String,
    pub page: i32,
    pub ordinal: i32,
    pub section: String,
    pub start_char: i32,
    pub end_char: i32,
    pub text: String,
}

/// A search hit: the row plus its cosine similarity (higher is better).
#[derive(Clone, Debug, PartialEq)]
pub struct RustChunkHit {
    pub row: RustChunkRow,
    pub score: f32,
}

#[flutter_rust_bridge::frb(opaque)]
pub struct NativeChunkStore {
    table: Table,
    dim: usize,
}

impl NativeChunkStore {
    /// Opens the store at `path`, creating the table when it does not exist.
    ///
    /// A table whose vector width disagrees with `dim` is an error rather than
    /// a silent reset: the collection's embedding profile changed and the data
    /// has to be rebuilt.
    pub fn open(path: String, dim: usize) -> Result<Self, String> {
        if dim == 0 {
            return Err("Vector dimensions must be positive".into());
        }
        rt().block_on(async move {
            // A bare Windows path parses as a one-character URI scheme; lancedb
            // special-cases that, but forward slashes avoid the question.
            let uri = path.replace('\\', "/");
            let connection = lancedb::connect(&uri)
                .execute()
                .await
                .map_err(|e| format!("Failed to open vector store at {path}: {e}"))?;

            let names = connection
                .table_names()
                .execute()
                .await
                .map_err(|e| format!("Failed to list tables at {path}: {e}"))?;

            let table = if names.iter().any(|name| name == TABLE_NAME) {
                let table = connection
                    .open_table(TABLE_NAME)
                    .execute()
                    .await
                    .map_err(|e| format!("Failed to open table at {path}: {e}"))?;
                let schema = table
                    .schema()
                    .await
                    .map_err(|e| format!("Failed to read table schema at {path}: {e}"))?;
                let existing = vector_dim(&schema)?;
                if existing != dim {
                    return Err(format!(
                        "{DIM_MISMATCH}: table stores {existing}-dimensional vectors, profile expects {dim}"
                    ));
                }
                table
            } else {
                connection
                    .create_empty_table(TABLE_NAME, chunk_schema(dim))
                    .execute()
                    .await
                    .map_err(|e| format!("Failed to create table at {path}: {e}"))?
            };

            Ok(Self { table, dim })
        })
    }

    /// Appends `rows` with their flattened `vectors` in a single transaction.
    pub fn add(&self, rows: Vec<RustChunkRow>, vectors: Vec<f32>) -> Result<(), String> {
        if rows.is_empty() {
            if !vectors.is_empty() {
                return Err(format!(
                    "Vector buffer size mismatch: expected 0 floats, got {}",
                    vectors.len()
                ));
            }
            return Ok(());
        }

        let expected = rows.len() * self.dim;
        if vectors.len() != expected {
            return Err(format!(
                "Vector buffer size mismatch: expected {} floats ({}x{}), got {}",
                expected,
                rows.len(),
                self.dim,
                vectors.len()
            ));
        }
        for vector in vectors.chunks_exact(self.dim) {
            validate_vector(vector)?;
        }

        let batch = build_batch(chunk_schema(self.dim), &rows, &vectors, self.dim)?;
        rt().block_on(async {
            self.table
                .add(batch)
                .execute()
                .await
                .map(|_| ())
                .map_err(|e| format!("Failed to add vectors: {e}"))
        })
    }

    /// Exact cosine search. Embeddings are L2-normalized by the caller, so the
    /// returned score is the cosine similarity.
    pub fn search(&self, query: Vec<f32>, k: usize) -> Result<Vec<RustChunkHit>, String> {
        if k == 0 {
            return Ok(vec![]);
        }
        if query.len() != self.dim {
            return Err(format!(
                "Query dimension mismatch: expected {}, got {}",
                self.dim,
                query.len()
            ));
        }
        validate_vector(&query)?;

        rt().block_on(async {
            // No ANN index is created: LanceDB brute-forces without one, which
            // matches the previous exact search and keeps results exact. Worth
            // revisiting above ~50k rows with `create_index(&["vector"], Index::Auto)`.
            let batches: Vec<RecordBatch> = self
                .table
                .query()
                .nearest_to(query.as_slice())
                .map_err(|e| format!("Failed to build search query: {e}"))?
                .distance_type(DistanceType::Cosine)
                .limit(k)
                .execute()
                .await
                .map_err(|e| format!("Search failed: {e}"))?
                .try_collect()
                .await
                .map_err(|e| format!("Search failed: {e}"))?;

            let mut hits = Vec::new();
            for batch in &batches {
                let distances = column::<Float32Array>(batch, "_distance")?;
                for (i, row) in rows_from_batch(batch)?.into_iter().enumerate() {
                    hits.push(RustChunkHit {
                        row,
                        score: 1.0 - distances.value(i),
                    });
                }
            }
            // Batch order is not guaranteed, so sort by score and break ties on
            // chunk id for a stable result.
            hits.sort_by(|a, b| {
                b.score
                    .total_cmp(&a.score)
                    .then_with(|| a.row.chunk_id.cmp(&b.row.chunk_id))
            });
            hits.truncate(k);
            Ok(hits)
        })
    }

    /// Non-vector scan of one page of one document, ordered by chunk ordinal.
    pub fn page_chunks(
        &self,
        doc_id: String,
        page: i32,
        limit: usize,
    ) -> Result<Vec<RustChunkRow>, String> {
        if limit == 0 {
            return Ok(vec![]);
        }
        let predicate = format!("doc_id = '{}' AND page = {}", escape_literal(&doc_id), page);
        rt().block_on(async {
            let batches: Vec<RecordBatch> = self
                .table
                .query()
                .only_if(predicate)
                .execute()
                .await
                .map_err(|e| format!("Page lookup failed: {e}"))?
                .try_collect()
                .await
                .map_err(|e| format!("Page lookup failed: {e}"))?;

            let mut rows = Vec::new();
            for batch in &batches {
                rows.extend(rows_from_batch(batch)?);
            }
            rows.sort_by_key(|row| row.ordinal);
            rows.truncate(limit);
            Ok(rows)
        })
    }

    /// Removes every row belonging to one document.
    pub fn delete_doc(&self, doc_id: String) -> Result<(), String> {
        let predicate = format!("doc_id = '{}'", escape_literal(&doc_id));
        self.delete_where(predicate)
    }

    /// Removes rows whose document is not in `doc_ids`, returning the number of
    /// documents dropped. This is the orphan sweep that replaces the old
    /// dirty/clean index-state protocol.
    ///
    /// Nothing is written when there is nothing stale — every write would
    /// otherwise append a dataset version on each app start.
    pub fn retain_docs(&self, doc_ids: Vec<String>) -> Result<usize, String> {
        let keep: HashSet<String> = doc_ids.into_iter().collect();
        let stale: Vec<String> = self
            .doc_ids()?
            .into_iter()
            .filter(|id| !keep.contains(id))
            .collect();
        if stale.is_empty() {
            return Ok(0);
        }
        let list = stale
            .iter()
            .map(|id| format!("'{}'", escape_literal(id)))
            .collect::<Vec<_>>()
            .join(", ");
        self.delete_where(format!("doc_id IN ({list})"))?;
        Ok(stale.len())
    }

    /// Distinct document ids currently in the table.
    pub fn doc_ids(&self) -> Result<Vec<String>, String> {
        rt().block_on(async {
            let batches: Vec<RecordBatch> = self
                .table
                .query()
                .select(Select::columns(&["doc_id"]))
                .execute()
                .await
                .map_err(|e| format!("Failed to list documents: {e}"))?
                .try_collect()
                .await
                .map_err(|e| format!("Failed to list documents: {e}"))?;

            let mut seen = HashSet::new();
            for batch in &batches {
                let doc_id = column::<StringArray>(batch, "doc_id")?;
                for i in 0..batch.num_rows() {
                    seen.insert(doc_id.value(i).to_string());
                }
            }
            let mut ids: Vec<String> = seen.into_iter().collect();
            ids.sort();
            Ok(ids)
        })
    }

    pub fn count(&self) -> Result<usize, String> {
        rt().block_on(async {
            self.table
                .count_rows(None)
                .await
                .map_err(|e| format!("Failed to count rows: {e}"))
        })
    }

    pub fn dim(&self) -> usize {
        self.dim
    }

    /// Compacts fragments and prunes superseded versions.
    ///
    /// Every append and delete creates a new dataset version, and Lance keeps
    /// them until told otherwise, so this runs after each import.
    pub fn compact(&self) -> Result<(), String> {
        rt().block_on(async {
            self.table
                .optimize(OptimizeAction::All)
                .await
                .map(|_| ())
                .map_err(|e| format!("Compaction failed: {e}"))
        })
    }

    #[flutter_rust_bridge::frb(ignore)]
    fn delete_where(&self, predicate: String) -> Result<(), String> {
        rt().block_on(async {
            self.table
                .delete(predicate.as_str())
                .await
                .map(|_| ())
                .map_err(|e| format!("Delete failed: {e}"))
        })?;
        self.compact()
    }
}

fn chunk_schema(dim: usize) -> SchemaRef {
    Arc::new(Schema::new(vec![
        Field::new("chunk_id", DataType::Utf8, false),
        Field::new("doc_id", DataType::Utf8, false),
        Field::new("page", DataType::Int32, false),
        Field::new("ordinal", DataType::Int32, false),
        Field::new("section", DataType::Utf8, false),
        Field::new("start_char", DataType::Int32, false),
        Field::new("end_char", DataType::Int32, false),
        Field::new("text", DataType::Utf8, false),
        Field::new(
            "vector",
            // The inner field must be named "item" and be nullable: that is the
            // Arrow/Lance convention for FixedSizeList vector columns.
            DataType::FixedSizeList(
                Arc::new(Field::new("item", DataType::Float32, true)),
                dim as i32,
            ),
            false,
        ),
    ]))
}

fn vector_dim(schema: &Schema) -> Result<usize, String> {
    let field = schema
        .field_with_name("vector")
        .map_err(|_| format!("{DIM_MISMATCH}: vector store is missing its vector column"))?;
    match field.data_type() {
        DataType::FixedSizeList(_, width) if *width > 0 => Ok(*width as usize),
        other => Err(format!(
            "{DIM_MISMATCH}: vector column has type {other:?}"
        )),
    }
}

fn build_batch(
    schema: SchemaRef,
    rows: &[RustChunkRow],
    vectors: &[f32],
    dim: usize,
) -> Result<RecordBatch, String> {
    let mut chunk_id = StringBuilder::new();
    let mut doc_id = StringBuilder::new();
    let mut page = Int32Builder::new();
    let mut ordinal = Int32Builder::new();
    let mut section = StringBuilder::new();
    let mut start_char = Int32Builder::new();
    let mut end_char = Int32Builder::new();
    let mut text = StringBuilder::new();
    let mut vector = FixedSizeListBuilder::new(Float32Builder::new(), dim as i32);

    for (i, row) in rows.iter().enumerate() {
        chunk_id.append_value(&row.chunk_id);
        doc_id.append_value(&row.doc_id);
        page.append_value(row.page);
        ordinal.append_value(row.ordinal);
        section.append_value(&row.section);
        start_char.append_value(row.start_char);
        end_char.append_value(row.end_char);
        text.append_value(&row.text);
        vector
            .values()
            .append_slice(&vectors[i * dim..(i + 1) * dim]);
        vector.append(true);
    }

    RecordBatch::try_new(
        schema,
        vec![
            Arc::new(chunk_id.finish()),
            Arc::new(doc_id.finish()),
            Arc::new(page.finish()),
            Arc::new(ordinal.finish()),
            Arc::new(section.finish()),
            Arc::new(start_char.finish()),
            Arc::new(end_char.finish()),
            Arc::new(text.finish()),
            Arc::new(vector.finish()),
        ],
    )
    .map_err(|e| format!("Failed to build record batch: {e}"))
}

fn column<'a, A: Array + 'static>(batch: &'a RecordBatch, name: &str) -> Result<&'a A, String> {
    batch
        .column_by_name(name)
        .ok_or_else(|| format!("Missing column: {name}"))?
        .as_any()
        .downcast_ref::<A>()
        .ok_or_else(|| format!("Column {name} has an unexpected Arrow type"))
}

fn rows_from_batch(batch: &RecordBatch) -> Result<Vec<RustChunkRow>, String> {
    let chunk_id = column::<StringArray>(batch, "chunk_id")?;
    let doc_id = column::<StringArray>(batch, "doc_id")?;
    let page = column::<Int32Array>(batch, "page")?;
    let ordinal = column::<Int32Array>(batch, "ordinal")?;
    let section = column::<StringArray>(batch, "section")?;
    let start_char = column::<Int32Array>(batch, "start_char")?;
    let end_char = column::<Int32Array>(batch, "end_char")?;
    let text = column::<StringArray>(batch, "text")?;

    Ok((0..batch.num_rows())
        .map(|i| RustChunkRow {
            chunk_id: chunk_id.value(i).to_string(),
            doc_id: doc_id.value(i).to_string(),
            page: page.value(i),
            ordinal: ordinal.value(i),
            section: section.value(i).to_string(),
            start_char: start_char.value(i),
            end_char: end_char.value(i),
            text: text.value(i).to_string(),
        })
        .collect())
}

/// Escapes a value for interpolation into a SQL string literal.
fn escape_literal(value: &str) -> String {
    value.replace('\'', "''")
}

fn validate_vector(vector: &[f32]) -> Result<(), String> {
    let finite_nonzero = !vector.is_empty()
        && vector.iter().all(|value| value.is_finite())
        && vector.iter().any(|value| *value != 0.0);
    if finite_nonzero {
        Ok(())
    } else {
        Err("Expected a finite non-zero vector".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(chunk_id: &str, doc_id: &str, page: i32, ordinal: i32, text: &str) -> RustChunkRow {
        RustChunkRow {
            chunk_id: chunk_id.to_string(),
            doc_id: doc_id.to_string(),
            page,
            ordinal,
            section: "Results".to_string(),
            start_char: 0,
            end_char: text.len() as i32,
            text: text.to_string(),
        }
    }

    fn store(dir: &tempfile::TempDir, dim: usize) -> NativeChunkStore {
        NativeChunkStore::open(dir.path().to_string_lossy().to_string(), dim).expect("open")
    }

    #[test]
    fn opens_creates_table_and_reports_dim() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 3);
        assert_eq!(s.dim(), 3);
        assert_eq!(s.count().unwrap(), 0);
    }

    #[test]
    fn searches_by_cosine_and_returns_metadata() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 3);
        s.add(
            vec![
                row("d:p1:c0", "d", 1, 0, "on the x axis"),
                row("d:p2:c0", "d", 2, 1, "on the y axis"),
                row("d:p3:c0", "d", 3, 2, "between them"),
            ],
            vec![1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.7071, 0.7071, 0.0],
        )
        .expect("add");

        let hits = s.search(vec![1.0, 0.0, 0.0], 2).expect("search");
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].row.chunk_id, "d:p1:c0");
        assert_eq!(hits[0].row.text, "on the x axis");
        assert_eq!(hits[0].row.page, 1);
        assert_eq!(hits[0].row.section, "Results");
        assert!((hits[0].score - 1.0).abs() < 1e-4);
        assert_eq!(hits[1].row.chunk_id, "d:p3:c0");
        assert!((hits[1].score - 0.7071).abs() < 1e-3);
    }

    #[test]
    fn reopening_sees_persisted_rows() {
        let dir = tempfile::tempdir().unwrap();
        {
            let s = store(&dir, 2);
            s.add(
                vec![row("d:p1:c0", "d", 1, 0, "persisted")],
                vec![1.0, 0.0],
            )
            .expect("add");
        }
        let reopened = store(&dir, 2);
        assert_eq!(reopened.count().unwrap(), 1);
        let hits = reopened.search(vec![1.0, 0.0], 1).expect("search");
        assert_eq!(hits[0].row.text, "persisted");
    }

    #[test]
    fn rejects_a_different_profile_dimension() {
        let dir = tempfile::tempdir().unwrap();
        drop(store(&dir, 3));
        // `expect_err` would need Debug on the store, which holds a Table.
        let err = match NativeChunkStore::open(dir.path().to_string_lossy().to_string(), 4) {
            Ok(_) => panic!("expected a dimension mismatch"),
            Err(e) => e,
        };
        assert!(err.starts_with(DIM_MISMATCH), "unexpected error: {err}");
    }

    #[test]
    fn reads_one_page_in_ordinal_order() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 2);
        s.add(
            vec![
                row("d:p1:c1", "d", 1, 1, "second"),
                row("d:p1:c0", "d", 1, 0, "first"),
                row("d:p2:c0", "d", 2, 2, "other page"),
                row("e:p1:c0", "e", 1, 0, "other doc"),
            ],
            vec![1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.5, 0.5],
        )
        .expect("add");

        let page = s.page_chunks("d".to_string(), 1, 4).expect("page");
        assert_eq!(page.len(), 2);
        assert_eq!(page[0].text, "first");
        assert_eq!(page[1].text, "second");
    }

    #[test]
    fn deletes_every_row_for_a_document() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 2);
        s.add(
            vec![
                row("d:p1:c0", "d", 1, 0, "keep me"),
                row("e:p1:c0", "e", 1, 0, "drop me"),
            ],
            vec![1.0, 0.0, 0.0, 1.0],
        )
        .expect("add");

        s.delete_doc("e".to_string()).expect("delete");
        assert_eq!(s.count().unwrap(), 1);
        assert_eq!(s.doc_ids().unwrap(), vec!["d".to_string()]);
    }

    #[test]
    fn retain_docs_drops_only_unknown_documents() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 2);
        s.add(
            vec![
                row("d:p1:c0", "d", 1, 0, "ready"),
                row("e:p1:c0", "e", 1, 0, "orphan"),
            ],
            vec![1.0, 0.0, 0.0, 1.0],
        )
        .expect("add");

        assert_eq!(s.retain_docs(vec!["d".to_string()]).unwrap(), 1);
        assert_eq!(s.doc_ids().unwrap(), vec!["d".to_string()]);
        // Nothing stale: no work, and no new dataset version.
        assert_eq!(s.retain_docs(vec!["d".to_string()]).unwrap(), 0);
    }

    #[test]
    fn rejects_a_wrong_width_query() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 3);
        let err = s.search(vec![1.0, 0.0], 1).expect_err("dimension mismatch");
        assert!(err.contains("Query dimension mismatch"), "got: {err}");
    }

    #[test]
    fn rejects_a_mismatched_vector_buffer() {
        let dir = tempfile::tempdir().unwrap();
        let s = store(&dir, 3);
        let err = s
            .add(vec![row("d:p1:c0", "d", 1, 0, "x")], vec![1.0, 0.0])
            .expect_err("buffer mismatch");
        assert!(err.contains("Vector buffer size mismatch"), "got: {err}");
    }
}
