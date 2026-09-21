# PaperChat

A Windows Flutter app for local research-paper collections, streamed AI chat, and saved citations. Indexing runs entirely through OpenRouter: every PDF page is rendered to an image and transcribed by a multimodal model, and an instruct model reports the paper's outline and bibliography. Quantized vector search runs in Rust.

## Project layout

```text
lib/
  main.dart                 # Startup and dependency overrides
  app/                      # App widget and shared Riverpod providers
  data/
    models/                 # Persisted models and JSON codecs
    services/               # Files, embeddings, the indexing pipeline, native index
    repositories/           # Paper import and per-collection index ownership
  domain/
    indexing/               # Transcript assembly, section resolution, chunking
    ...                     # Retrieval and the bounded research tool loop
  ui/
    chat/                   # Chat controller, conversation, composer
    collections/            # Sidebar and import controller
    settings/               # Settings dialog
    sources/                # Saved excerpts and PDF viewer
    shell/                  # Desktop layout
    core/                   # Shared theme
packages/paper_native/       # Rust crate, bridge code, and Windows build support
  rust/src/api/             # Handwritten Rust
  lib/src/rust/             # Generated Dart bindings
  cargokit/                 # Vendored upstream build tooling
  windows/                  # Native build/bundling configuration
test/                       # Models, services, controllers, and widget tests
```

Views render state and handle UI actions; controllers coordinate operations. `PaperRepository` owns the native index for one collection and orchestrates import using concrete services. Riverpod supplies dependencies without another DI framework. Models use simple JSON codecs; generated bridge code stays in the native package.

## Indexing pipeline

`IndexingPipeline` turns one PDF into sections, chunks and references:

1. **Transcribe.** `PageRenderService` renders every page to PNG and
   `PageTranscriptionService` transcribes it to Markdown with the configured
   vision model (`qwen/qwen3-vl-235b-a22b-instruct` by default), four pages at
   a time. Because the page image is the only
   input, page N of the transcript is page N of the PDF — scanned and
   born-digital papers take the same path.
2. **Assemble.** `DocumentTranscript` stitches the pages into one string and
   remembers each page's span, so any character offset maps back to a page. A
   second view interleaves `<!-- PAGE N -->` markers for the model.
3. **Analyze.** `InstructDocumentService` asks the indexing model
   (`qwen/qwen3-235b-a22b-2507` by default, text-only with 262K context) for
   the paper's title, authors and outline. It returns *headings and page
   numbers*, never body text, so nothing the model writes can end up in the
   indexed content.
4. **Resolve.** `SectionResolver` anchors each heading back into the transcript
   and gives it the span up to the next heading. The sections tile the document
   with no gaps or overlap.
5. **Read the bibliography.** Once the sections exist, the references section
   alone is sent back to the same model, split into windows of ~12K characters
   at entry boundaries. Outline and bibliography are deliberately *not* asked
   for in one response: a paper with a few hundred references overruns the
   model's output budget, and a JSON object cut off mid-entry is worth nothing.
   A window that still truncates raises `InstructTruncatedException`, which
   names the real cause instead of surfacing a parse error hundreds of lines
   in. If the outline missed the "References" heading, the last such heading in
   the transcript is used instead, so the bibliography is not silently lost.
6. **Chunk.** `SectionChunker` cuts overlapping chunks inside each section,
   breaking on paragraph, then sentence, then word. Chunks carry their section,
   page and absolute offsets. The bibliography is not chunked: it is kept as
   structured `PaperReference` entries for the references view and for a
   validating agent to check.

Indexing uses its own two models, set in Settings and separate from the chat
model: `transcriptionModel` must accept image input, `indexingModel` never sees
an image and only needs a long context.

Any failure aborts the import and the paper is stored as `failed` with the
reason — a partially transcribed paper would index as a quietly incomplete
document. Papers imported before this pipeline report `isStale` and need a
re-import to gain sections.

`ResearchAgent` uses the existing LangChain packages for typed messages, streamed response parsing, and tool-call concatenation. It allows four model requests and four tool executions per turn, including initial retrieval. `http` supplies embedding retries; the Rust `turbovec` crate supplies top-k selection.

## Build and run

Requirements: Flutter with Dart **3.13.2 or newer**, Rust/Cargo with the Windows MSVC target, Visual Studio's Desktop development with C++ workload, and Windows Developer Mode for Flutter plugin symlinks. The app currently targets Windows.

```powershell
flutter pub get
flutter run -d windows
flutter build windows --release
```

Cargokit builds and bundles `lab_05_rust.dll` automatically during Windows builds. Distribute the entire `build/windows/x64/runner/Release/` directory, including `data/` and the DLLs. End users do not need Rust installed.

## Checks

```powershell
flutter analyze
flutter test --exclude-tags native
cargo test --locked --manifest-path packages/paper_native/rust/Cargo.toml
cargo build --release --locked --manifest-path packages/paper_native/rust/Cargo.toml
flutter test --tags native
```

After building the native library, `flutter test` runs all tests together. Network tests use fake HTTP responses and do not call paid APIs. Native service tests check persistence, existing TVEC files, corrupt-file handling, collection isolation, and a full paper import against the real index.

To regenerate bindings after Rust API changes, see [the native package instructions](packages/paper_native/README.md). Do not edit generated files directly.

## Existing data

The application-support `PaperChat/` directory and JSON formats are unchanged. An old `.key_store` file is imported into settings once and then removed; saving an empty key keeps it cleared. Credentials retain the existing settings-file storage behavior.

The index is the upstream **[`turbovec`](https://crates.io/crates/turbovec) engine**, wrapped by `NativeVectorIndex`. It uses `IdMapIndex`, which keeps the existing `u64` chunk vector IDs across adds, removals and reloads, and stores its own `.tvim` files at the unchanged `vectors.tvim` path.

Two constraints follow from the engine:

- **Embedding dimensions must be a positive multiple of 8.** The default 768 qualifies, as do the common 1536 and 3072. A `defaultEmbeddingDimensions` that does not is rejected when the index is created.
- **`bitWidth` must be 2, 3, or 4** and now genuinely selects quantization. The default remains 4. Search is approximate rather than exact: vectors are compressed to 4 bits per coordinate, which is what makes it fast and small, but a top-k result set is no longer guaranteed identical to a full cosine scan.

Index files written before this engine, which used the `TVEC` version-1 layout, are not readable and must be rebuilt by reimporting the collection. Invalid indexes fail visibly instead of silently resetting. Scanned PDFs still require OCR, which is not implemented.
