# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PaperChat (package name `lab_05`): a Windows-only Flutter desktop app for local research-paper collections with streamed, citation-grounded AI chat. PDF extraction and LanceDB vector + chunk storage run in Rust via flutter_rust_bridge; OpenRouter supplies embeddings, chat, and vision OCR.

## Commands

```powershell
flutter pub get
flutter run -d windows
flutter build windows --release
flutter analyze
```

Building the Rust crate requires **`protoc`** on `PATH` (or `PROTOC` pointing at it): the `lance-*` build scripts run `prost_build`. Install with `winget install --id Google.Protobuf -e` and restart the shell. The dependency tree is large (Arrow + DataFusion + Lance: 568 crates, up from 182), so the first build takes roughly 10 minutes and the DLL grows from ~7 MB to ~240 MB; incremental rebuilds of `lab_05_rust` itself stay fast. `strip` does not help on windows-msvc (debug info goes to a separate `.pdb`).

Tests are split by whether they need the native DLL:

```powershell
flutter test --exclude-tags native          # pure Dart/widget tests
cargo build --release --locked --manifest-path packages/paper_native/rust/Cargo.toml
flutter test --tags native                  # requires the DLL built above
cargo test --locked --manifest-path packages/paper_native/rust/Cargo.toml
```

Single test file / single test:

```powershell
flutter test test/domain/research_agent_test.dart
flutter test test/domain/research_agent_test.dart --plain-name "substring of test name"
```

`test/data/services/native_services_test.dart` is the only `@Tags(['native'])` file; it loads `packages/paper_native/rust/target/release/lab_05_rust.dll` by relative path in `setUpAll`, so run it from the repo root. It covers chunk round-trips and reopen, page lookups, delete-by-document, the stale-row sweep, profile-dimension mismatch, corrupt-store handling, per-collection isolation, and the PDF chunking bridge. `initializeNative` takes an optional `libraryPath` and nothing else. Network tests use fake `http.Client` responses — no test calls paid APIs.

Regenerating the bridge after changing `packages/paper_native/rust/src/api/*.rs`: see [packages/paper_native/README.md](packages/paper_native/README.md). Generator, Rust crate, and Dart package are all pinned to flutter_rust_bridge **2.13.0**. Never hand-edit `packages/paper_native/lib/src/rust/**` or `rust/src/frb_generated.rs` (both are analyzer-excluded).

`analysis_options.yaml` turns on `strict-casts`, `strict-inference`, and `strict-raw-types` — new code must satisfy these.

## Architecture

Layering is `ui → domain → data`, wired by Riverpod; there is no other DI. Views render state and dispatch; controllers (`StateNotifier`) own operations.

**Startup** ([lib/main.dart](lib/main.dart)) is where the whole object graph is seeded: `initializeNative()` loads the DLL, `LocalStorage.createDefault()` takes an exclusive `app.lock` and runs crash recovery, then `localStorageProvider`, `settingsProvider`, and `currentCollectionProvider` are overridden in `ProviderScope`. `localStorageProvider` throws unless overridden — tests must override it too.

**Storage** ([lib/data/services/local_storage.dart](lib/data/services/local_storage.dart)) is the single source of truth for on-disk layout under `<appSupport>/PaperChat/`: `collections/<id>/{collection.json,documents/,metadata/,index/lance/,chats/}` plus a root `settings.json`. Always derive paths from its path getters rather than composing strings. All JSON writes go through `writeJsonSafely` (temp sibling + rename) — never point it inside `index/lance/`, which LanceDB owns. `runStartupRecovery()` retires a pre-LanceDB `index/vectors.tvim`, marks that collection's `ready` papers `needsReindex`, and flips dangling `processing` papers to `failed`.

**Collection ↔ index ownership** is the central invariant: one `CollectionIndex` (one LanceDB table) belongs to exactly one collection, provided by `paperRepositoryProvider` as a `Provider.family` keyed on collection id, disposed with the family entry. Never share or reuse an index across collections. Rows are keyed by the chunk's own id — there are no vector ids to mint. A table whose `FixedSizeList` vector width disagrees with the collection's `EmbeddingProfile.dimensions` throws instead of silently resetting. A second invariant now carries the crash safety that `index/state.json` used to: **the table holds rows only for `ready` documents**, enforced by a sweep on every store open. Close the store before deleting a collection directory — Windows will not remove a directory with open LanceDB handles.

**Import pipeline** ([lib/data/repositories/paper_repository.dart](lib/data/repositories/paper_repository.dart)) is the most intricate flow: SHA-256 dedupe within the collection → copy PDF → persist metadata as `processing` → Rust `parse_pdf` → OCR any `needsOcrPages` → embed → a single transactional `add` into the LanceDB table → mark paper `ready` → compact. Failure paths persist the paper as `failed` with the error text. OCR runs a vision chat model on rendered pages (3 concurrent, any page failure fails the import); a page that was OCR'd drops its text chunks entirely so the two chunk families never interleave, OCR chunk ids carry `:ocr`, and the Dart section-heading regex deliberately mirrors `section_regex` in `rust/src/api/pdf_parser.rs` — change both together.

**Retrieval and the agent**: [lib/domain/retrieval.dart](lib/domain/retrieval.dart) embeds the query, searches the collection's table, and dedupes by `(doc, page, startChar)`. There is no allowlist and no disk scan: hits carry their own text, page and offsets, and the table only holds ready documents. [lib/domain/research_agent.dart](lib/domain/research_agent.dart) runs a bounded tool loop on top of LangChain (`ChatOpenAI` streaming, `ChatResult.concat`): **4 model steps and 4 tool executions per turn, with the initial retrieval counting as tool #1**. Tools are `search_papers`, `read_page`, `list_papers`. It emits a `ChatEvent` stream (`ToolStatus` / `SourcesUpdated` / `TextChunk` / `ChatDone` / `ChatError`) that `ChatController` folds into `ChatState`. The `_Evidence` map assigns `[S1]`, `[S2]` ids per turn; those ids are turn-local, which is why `_history` strips `[Sn]` markers from replayed messages. Paper excerpts are treated as untrusted data in the system prompt — preserve that framing.

**Native package** ([packages/paper_native](packages/paper_native)): crate and Dart package are both named `lab_05_rust` to keep the DLL name stable. `lance_store.rs` wraps a LanceDB table holding each chunk's vector *and* its metadata and text (Arrow `FixedSizeList<Float32, dim>` for the vector). Search is exact brute-force cosine — no ANN index is created, which is right below roughly 50k rows. lancedb is async/tokio-only, so the exported functions stay synchronous and block on a process-wide tokio runtime; FRB dispatches them on its own worker pool, never a tokio thread. Invalid or profile-mismatched tables fail loudly. **lancedb is pinned to `0.39.0` with the `remote` feature**: without it the crate does not compile, because `job.rs` uses an `Error::Http` variant that is gated behind `remote`. 0.37.1 avoids that bug but pins `time = "=0.3.47"`, which breaks `lopdf 0.44`. `pdf_parser.rs` does `pdf-inspector` extraction, page-aware chunking with overlap, and flags pages needing OCR. Cargokit compiles and bundles the DLL during `flutter build windows`; end users need no Rust toolchain, but the whole `build/windows/x64/runner/Release/` tree (including `data/` and DLLs) must ship together.

**Settings and endpoints**: `AppSettings.apiBaseUrl` normalizes a user-supplied OpenRouter base URL (strips trailing slashes and a trailing `/chat/completions` or `/embeddings`); build request URLs from `chatCompletionsUrl` / `embeddingsUrl`, never by string concatenation. `AppSettings.fromJson` also accepts the legacy `baseUrl` / `apiKey` keys. The API key lives in `settings.json`; a legacy `.key_store` file is migrated once and deleted.

[docs/archive/IMPLEMENTATION_PLAN.md](docs/archive/IMPLEMENTATION_PLAN.md) is historical context only — the code and the READMEs describe current behavior.
