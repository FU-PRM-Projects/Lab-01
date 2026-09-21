# PaperChat

A Windows Flutter app for local research-paper collections, streamed AI chat, and saved citations. PDF extraction and LanceDB-backed vector search run in Rust; OpenRouter handles embeddings and chat generation.

## Project layout

```text
lib/
  main.dart                 # Startup and dependency overrides
  app/                      # App widget and shared Riverpod providers
  data/
    models/                 # Persisted models and JSON codecs
    services/               # Files, embeddings, PDF extraction, vector store
    repositories/           # Paper import and per-collection index ownership
  domain/                   # Retrieval and the bounded research tool loop
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
docs/archive/               # Original implementation proposal
```

Views render state and handle UI actions; controllers coordinate operations. `PaperRepository` owns the LanceDB chunk store for one collection and orchestrates import using concrete services. Riverpod supplies dependencies without another DI framework. Models use simple JSON codecs; generated bridge code stays in the native package.

`ResearchAgent` uses the existing LangChain packages for typed messages, streamed response parsing, and tool-call concatenation. It allows four model requests and four tool executions per turn, including initial retrieval. `http` supplies embedding retries; Rust `itertools` supplies top-k selection.

## Build and run

Requirements: Flutter with Dart **3.13.2 or newer**, Rust/Cargo with the Windows MSVC target, Visual Studio's Desktop development with C++ workload, **`protoc`** on `PATH`, and Windows Developer Mode for Flutter plugin symlinks. The app currently targets Windows.

`protoc` is required because the `lance-*` crates generate their protobuf code at build time:

```powershell
winget install --id Google.Protobuf -e
```

Restart the shell afterwards so `protoc` is visible to the process that runs `flutter run`; alternatively set `PROTOC` to the executable's full path. The vector store pulls in Arrow, DataFusion and Lance (568 crates, up from 182), so the **first** Rust build takes roughly 10 minutes and `lab_05_rust.dll` grows from ~7 MB to ~240 MB; later builds are incremental (seconds). Plan for that in the shipped bundle. Excluding `packages/paper_native/rust/target` from Windows Defender is worth doing.

```powershell
flutter pub get
flutter run -d windows
flutter build windows --release
```

Cargokit builds and bundles `lab_05_rust.dll` automatically during Windows builds. It compiles into its own target directory (`build/windows/x64/plugins/lab_05_rust/cargokit_build/`), **not** `packages/paper_native/rust/target/`, so the first `flutter build windows` after a clone or a `flutter clean` recompiles the whole dependency tree again even if `cargo build` has already been run. Expect ~10 minutes there; later builds reuse that directory. Distribute the entire `build/windows/x64/runner/Release/` directory, including `data/` and the DLLs. End users do not need Rust installed.

## Checks

```powershell
flutter analyze
flutter test --exclude-tags native
cargo test --locked --manifest-path packages/paper_native/rust/Cargo.toml
cargo build --release --locked --manifest-path packages/paper_native/rust/Cargo.toml
flutter test --tags native
```

After building the native library, `flutter test` runs all tests together. Network tests use fake HTTP responses and do not call paid APIs. Native service tests check chunk round-trips and reopen, page lookups, delete-by-document, the stale-row sweep, profile-dimension mismatch, corrupt-store handling, collection isolation, and the PDF chunking bridge.

To regenerate bindings after Rust API changes, see [the native package instructions](packages/paper_native/README.md). Do not edit generated files directly.

## Existing data

The application-support `PaperChat/` directory and JSON formats are unchanged. An old `.key_store` file is imported into settings once and then removed; saving an empty key keeps it cleared. Credentials retain the existing settings-file storage behavior.

Vectors and chunk metadata live together in a **LanceDB** table under `collections/<id>/index/lance/`. Search is exact brute-force cosine; no approximate index is built. Invalid or profile-mismatched tables fail visibly instead of silently resetting. Scanned PDFs are handled by vision OCR during import.

**Upgrading from a pre-LanceDB install is a clean break.** The old `index/vectors.tvim` held only raw vectors, and they cannot be re-keyed into the new schema, so on first launch that file and `index/state.json` are deleted and the collection's papers are marked "needs re-import". Their PDFs and chat history are kept — re-import a paper from the sidebar to make it searchable again.

The [original proposal](docs/archive/IMPLEMENTATION_PLAN.md) is archived historical context. This README describes the current code.
