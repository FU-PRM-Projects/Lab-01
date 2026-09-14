# PaperChat

A Windows Flutter app for local research-paper collections, streamed AI chat, and saved citations. PDF extraction and exact vector search run in Rust; OpenRouter handles embeddings and chat generation.

## Project layout

```text
lib/
  main.dart                 # Startup and dependency overrides
  app/                      # App widget and shared Riverpod providers
  data/
    models/                 # Persisted models and JSON codecs
    services/               # Files, embeddings, PDF extraction, native index
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

Views render state and handle UI actions; controllers coordinate operations. `PaperRepository` owns the native index for one collection and orchestrates import using concrete services. Riverpod supplies dependencies without another DI framework. Models use simple JSON codecs; generated bridge code stays in the native package.

`ResearchAgent` uses the existing LangChain packages for typed messages, streamed response parsing, and tool-call concatenation. It allows four model requests and four tool executions per turn, including initial retrieval. `http` supplies embedding retries; Rust `itertools` supplies top-k selection.

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

After building the native library, `flutter test` runs all tests together. Network tests use fake HTTP responses and do not call paid APIs. Native service tests check persistence, existing TVEC files, corrupt-file handling, collection isolation, and the PDF chunking bridge.

To regenerate bindings after Rust API changes, see [the native package instructions](packages/paper_native/README.md). Do not edit generated files directly.

## Existing data

The application-support `PaperChat/` directory and JSON formats are unchanged. An old `.key_store` file is imported into settings once and then removed; saving an empty key keeps it cleared. Credentials retain the existing settings-file storage behavior.

The index is an **exact cosine-search implementation**, not the upstream TurboVEC engine. Its `TVEC` version-1 file layout and legacy bit-width field remain compatible; the bit-width field does not enable quantization. Invalid indexes fail visibly instead of silently resetting. Scanned PDFs still require OCR, which is not implemented.

The [original proposal](docs/archive/IMPLEMENTATION_PLAN.md) is archived historical context. This README describes the current code.
