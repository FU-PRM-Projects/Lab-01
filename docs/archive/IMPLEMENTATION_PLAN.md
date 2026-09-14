# Research Paper Chat: V1 Implementation Plan

Status: proposed implementation plan. No application implementation is implied by this document.

Planning baseline: 14 September 2026. The workspace currently contains a Windows Flutter starter with a Dart SDK constraint of `^3.13.2`. Package versions and native builds must pass the compatibility milestone below before being pinned.

## 1. Product outcome and boundaries

Build a local-first Flutter desktop application for chatting with collections of research-paper PDFs. Use a narrow collections/chat sidebar, a spacious conversation area, a bottom composer, and a source panel that opens when needed. The supplied screenshot is visual inspiration; text inside it is not an additional specification.

The essential user experience is:

```text
Import a paper
→ ask a question
→ receive a streamed answer with inline citations
→ click a citation
→ inspect the supporting excerpt
→ open the copied PDF at the cited passage
→ reopen the same citation after restarting the app
```

All PDFs, extracted content, vector indexes, settings, and conversations are stored locally. PDF extraction, chunking, vector search, and source inspection run locally. OpenRouter performs embedding and language-model inference. Embedding requests send chunk text; generation requests send selected evidence and conversation context. Explain this once during API-key setup. Existing documents, chats, and citations remain browsable offline.

V1 includes collection creation/rename/deletion, PDF import/removal/retry, text extraction, chunking, Gemini embeddings, persistent TurboVEC search, simple retrieval, one research agent, streaming, cancellation, local chat history, and inspectable citations.

Defer OCR, automatic figure selection, table reconstruction, reranking, hybrid search, query-rewriting models, summarization, graph retrieval, and full-text search. Keep image embedding in the same embedding client, but normal PDF imports embed text only.

There is no backend server or database. Do not introduce repositories, generic storage interfaces, DI frameworks, an event bus, an agent framework around the agent, or a migration framework.

## 2. Packages and integration decisions

| Package | Use | Reason |
| --- | --- | --- |
| Flutter SDK | Desktop widgets, navigation, keyboard behavior | Existing project; enough for a minimal desktop shell |
| `flutter_riverpod` | UI state and the chat controller | Direct state management without code generation or a separate DI system |
| `langchain_core` | Messages, tool specifications, streamed-result concatenation | Supplies the types needed by a small tool loop |
| `langchain_openai` | OpenRouter chat generation | Supports an OpenAI-compatible base URL, streaming, and tool calls |
| `http` | Embedding calls and request-scoped HTTP clients | Direct JSON requests keep provider-specific embedding inputs easy to inspect |
| `pdfrx` | PDF extraction and viewing | One PDFium-backed package covers page text, text geometry, local rendering, and navigation |
| `saia_turbovec` | Native vector computation | Existing Dart FFI binding with insertion, search, removal, and persistence; subject to Windows validation |
| `file_picker` | Select one or more PDFs | Native desktop selection |
| `path_provider`, `path` | Application-support directory and path joining | Correct storage locations and platform-aware paths |
| `flutter_secure_storage` | OpenRouter API key | Keep credentials outside ordinary JSON and the source tree |
| `flutter_markdown_plus` | Assistant Markdown and citation rendering | Use its rendering hooks for application-owned citation links |
| `uuid` | Collection, document, message, and chat IDs | Names can change without changing identity |
| `crypto` | SHA-256 document hashes | Duplicate detection and verification of cited document identity |

Use manual `toJson`/`fromJson`. Add no Freezed, build_runner, Retrofit, or broader `langchain` dependency unless a concrete missing capability requires it. Use Flutter's existing test tools and direct test fakes; do not introduce a mocking framework by default.

Commit `pubspec.lock` for the application. Pin a compatible native TurboVEC build as well as its Dart binding. Document native build inputs and bundle the DLL with release output; the installed app must not require a compiler or a developer-machine path.

### TurboVEC qualification

The preferred engine remains TurboVEC. `saia_turbovec` is a binding to Rust through FFI, not a pure Dart port. Its published documentation requires a separately built Windows DLL. Its current native provenance notes also describe a local `capi.rs` bridge absent from upstream. Compiling upstream Rust alone is therefore not yet a verified integration recipe.

The first milestone must obtain or reproducibly build the matching C bridge and DLL, verify exported symbols and error handling, and exercise the packaged Windows application. Do not assume the Dart binding exposes newer upstream persistence features: its documented `write/load` operations are the baseline.

If this cannot be made reproducible with a small native bridge, record the exact blocker before proceeding with dependent code. A different embedded library would be an explicit plan revision, not a silent runtime fallback. Do not implement two vector engines in V1.

## 3. Small code organization

```text
lib/
├── main.dart
├── models/
│   ├── collection.dart
│   ├── paper.dart          # PaperDocument and PaperChunk
│   ├── chat.dart           # Chat and ChatMessage
│   └── citation.dart
├── storage/
│   └── local_storage.dart
├── pdf/
│   └── pdf_processor.dart
├── ai/
│   ├── embeddings.dart
│   ├── collection_index.dart
│   ├── retrieval.dart      # A function and small result type
│   └── research_agent.dart # Agent, chat events, chat-model construction
├── import_paper.dart       # Straight-line import function
└── ui/
    ├── providers.dart
    ├── chat_controller.dart
    ├── app_shell.dart
    ├── sidebar.dart
    ├── chat_page.dart
    ├── collection_page.dart
    ├── source_panel.dart
    ├── pdf_viewer.dart
    └── settings_dialog.dart
```

| Main class | Responsibility |
| --- | --- |
| `LocalStorage` | Read/write JSON, derive managed paths, enumerate objects, and replace files safely |
| `PdfProcessor` | Extract page text, identify basic section hints, and produce traceable chunks |
| `EmbeddingClient` | OpenRouter text/batch/image embedding calls and response validation |
| `CollectionIndex` | Own one native index, its persistence, ID lookup, and per-collection mutation serialization |
| `ResearchAgent` | Prepare evidence, dispatch three tools, and stream bounded responses |
| `ChatController` | Own active chat state, subscription, cancellation, and chat saves |

`retrieve()` and `importPaper()` are functions. Pass the concrete objects they need as arguments. Riverpod exposes application state and these concrete objects directly. Avoid a provider for every helper function.

The agent does not save chats or decide filesystem paths. The UI does not call TurboVEC or construct OpenRouter payloads.

## 4. Local folder structure

```text
<ApplicationSupport>/PaperChat/
├── settings.json
└── collections/
    └── <collectionId>/
        ├── collection.json
        ├── documents/
        │   └── <documentId>.pdf
        ├── metadata/
        │   └── <documentId>.json
        ├── index/
        │   ├── vectors.tvim
        │   └── state.json
        └── chats/
            └── <chatId>.json
```

Use generated IDs in paths and display names in JSON. Derive PDF paths from the selected collection and document IDs. Never persist the user's original import path as a dependency. Renaming a collection changes its metadata only.

Discover papers from `metadata/` and chats from `chats/`; do not duplicate those lists in `collection.json`. Ignore temporary/backup files during enumeration. Each JSON file represents one logical object. Native vector bytes are the intentional binary exception.

## 5. JSON formats and identity

The examples below are proposed application schemas. All timestamps are UTC ISO 8601. Use a `schemaVersion` field to detect unsupported files; do not build migrations before they are needed.

### Settings and collection

`settings.json` contains theme and inference defaults, never the API key:

```json
{
  "schemaVersion": 1,
  "theme": "dark",
  "chatModel": "<selected OpenRouter chat model ID>",
  "defaultEmbeddingModel": "google/gemini-embedding-2",
  "defaultEmbeddingDimensions": 768
}
```

`collection.json` pins the embedding configuration used by its index:

```json
{
  "schemaVersion": 1,
  "id": "collection_123",
  "name": "GraphRAG",
  "createdAt": "2026-09-14T08:00:00Z",
  "nextVectorId": 101,
  "embeddingProfile": {
    "id": "profile_123",
    "model": "google/gemini-embedding-2",
    "dimensions": 768,
    "inputFormatVersion": 1,
    "normalization": "l2"
  }
}
```

Changing global defaults affects new collections. Changing an existing collection's embedding profile requires an explicit full re-index operation. Do not query or insert into an old index with a new model merely because the dimensions happen to match.

Reserve monotonically increasing, positive vector IDs by saving `nextVectorId` before use. Gaps are acceptable; never recycle IDs. Serialize allocations with other mutations for that collection.

### Paper and chunks

```json
{
  "schemaVersion": 1,
  "id": "paper_abc",
  "fileName": "HippoRAG.pdf",
  "title": "HippoRAG",
  "authors": [],
  "sha256": "<hash of the managed PDF>",
  "pageCount": 18,
  "status": "ready",
  "error": null,
  "createdAt": "2026-09-14T08:01:00Z",
  "embeddingProfileId": "profile_123",
  "extractionVersion": 1,
  "chunkingVersion": 1,
  "chunks": [
    {
      "id": "paper_abc:p5:c0",
      "vectorId": 100,
      "page": 5,
      "ordinal": 0,
      "section": "Retrieval",
      "startChar": 1240,
      "endChar": 1880,
      "text": "<exact extracted passage spanning the recorded range>"
    }
  ]
}
```

Document states: `processing`, `ready`, `failed`, `needsReindex`, and `deleting`. An interrupted import becomes `failed` with an explanatory error and a Retry action.

At runtime, `PaperChunk` includes the parent `documentId` and access to its filename/title. Do not duplicate the filename in every serialized chunk. Keep `text`, physical page, source range, section, and vector ID available without a large document-object hierarchy.

The `vectorId → PaperChunk` lookup is rebuilt in memory from document metadata. There is no second JSON mapping of every chunk.

### Index checkpoint

`index/state.json` is a small checkpoint for the native snapshot, not a database or job system:

```json
{
  "schemaVersion": 1,
  "status": "clean",
  "embeddingProfileId": "profile_123",
  "dimensions": 768,
  "bitWidth": 4,
  "vectorCount": 100,
  "pending": null
}
```

Before index mutations, save `status: "dirty"` with a `pending` record containing the operation and document ID. Mark it `clean` only after the snapshot and document metadata are consistent. `needsReindex` means search is unavailable until repaired. Section 8 defines the exact ordering.

### Chat and citation snapshot

```json
{
  "schemaVersion": 1,
  "id": "chat_xyz",
  "collectionId": "collection_123",
  "title": "HippoRAG discussion",
  "createdAt": "2026-09-14T08:02:00Z",
  "updatedAt": "2026-09-14T08:03:00Z",
  "messages": [
    {
      "id": "message_12",
      "role": "assistant",
      "status": "complete",
      "content": "The method uses Personalized PageRank [S1].",
      "createdAt": "2026-09-14T08:03:00Z",
      "model": "<OpenRouter chat model ID used for this answer>",
      "citations": [
        {
          "sourceId": "S1",
          "documentId": "paper_abc",
          "documentHash": "<hash of the managed PDF>",
          "fileName": "HippoRAG.pdf",
          "title": "HippoRAG",
          "page": 5,
          "section": "Retrieval",
          "chunkId": "paper_abc:p5:c0",
          "extractionVersion": 1,
          "startChar": 1240,
          "endChar": 1880,
          "excerpt": "<the exact evidence passage supplied to the model>"
        }
      ]
    }
  ]
}
```

Assistant message states are `complete`, `cancelled`, and `failed`. Streaming is an in-memory state. User messages use the same basic message shape with no citations. Derive chat titles from the first user message without an extra model call.

## 6. PDF extraction and chunking

Use `pdfrx` for both extraction and viewing. Initialize its engine as required by the selected package version and close documents/rendered resources when no longer used.

1. Open the managed PDF and inspect page count and readability.
2. Extract structured text page by page so text ranges can be related to geometry.
3. Use physical PDF page numbers starting at 1. Keep printed page labels separate if later supported.
4. Use PDF properties or outlines for title/section hints when available; otherwise use the filename and conservative heading patterns. Unknown authors remain an empty list.
5. Split within each page at paragraph or sentence boundaries, falling back to word boundaries for long passages.
6. Target roughly 500–800 tokens with about 80 tokens of overlap. Use conservative character limits initially, such as a 2,400-character target, 3,200-character ceiling, and up to 320 characters of overlap. These are estimates, not tokenizer guarantees.
7. Save offsets into the original extracted page-text representation and the corresponding substring. Avoid whitespace normalization or dehyphenation that would invalidate offsets.

Verify how the chosen PDF API indexes Unicode characters; do not assume Dart string offsets and native PDF character indices are interchangeable. Use its text-range/geometry APIs for highlighting and cover non-ASCII text in the extraction proof.

Tables and captions remain text when extraction provides them. Do not claim structured table or image extraction from page rendering. No automatic page-image embedding occurs.

Image-only PDFs remain viewable and display an OCR-required indexing error. Mixed PDFs report pages with missing text. Password-protected or damaged PDFs report actionable failures. Do not mark a document searchable with zero useful chunks.

Test two-column papers before expanding extraction heuristics. Use package asynchronous APIs first; move application-owned CPU-heavy work off the UI thread when profiling shows blocking. Any native index handle used in a worker must be created, used, and closed in that same worker.

## 7. Embeddings and vector search

### OpenRouter embeddings

Use `POST https://openrouter.ai/api/v1/embeddings` from `EmbeddingClient` with the user-supplied bearer token. The selected initial model is `google/gemini-embedding-2` at 768 dimensions, subject to a real route/capability test.

Provide small methods:

```dart
Future<List<double>> embedText(String text);
Future<List<List<double>>> embedTexts(List<String> texts);
Future<List<double>> embedImage(Uint8List image);
```

Keep document/query input formatting inside this class. Verify model-specific task/instruction handling with the selected OpenRouter route rather than assuming the generic `input_type` field has identical behavior for every provider. Pin that behavior in `inputFormatVersion`.

Batch conservatively by input size and provider limits. Validate the returned input indices, count, dimensions, finite values, and nonzero norms. Normalize document and query vectors consistently before TurboVEC use. Never truncate, pad, or silently accept mismatched vectors.

Retry transient network/rate-limit failures with a small bounded backoff that honors cancellation and `Retry-After`. Authentication, credit, and invalid-input errors require a clear user action. Do not enable overlapping automatic retry loops in multiple libraries.

`embedImage` accepts explicitly supplied local image bytes and the verified multimodal request format. Test it separately; do not add figure discovery, image-management UI, or page rasterization to the import pipeline.

### CollectionIndex

Expose only the operations the application needs:

```dart
Future<void> add(List<PaperChunk> chunks, List<List<double>> vectors);
Future<List<SearchResult>> search(List<double> query, {int topK = 15});
Future<void> removeDocument(String documentId);
Future<void> save();
Future<void> close();
```

These are proposed application methods, not claims about the package's exact signatures. Keep native ID conversion, dimension checks, quantization configuration, result mapping, and memory cleanup inside this class. Open only the collection indexes needed by the UI.

Index only compatible `ready` documents for search, using the library's candidate allowlist when necessary. Never return evidence from another collection, failed documents, or documents being removed. A `Future` wrapper alone does not make synchronous FFI computation nonblocking; profile representative collections.

Do not store an additional full-precision embedding cache in V1. This keeps disk formats small, with the explicit tradeoff that a complete index rebuild can require new embedding requests.

## 8. Import, persistence, recovery, and deletion

Use a few file helpers in `LocalStorage`: read JSON, write JSON through a temporary sibling, derive managed paths, and enumerate objects. Validate parsed data and identifiers before constructing paths. A malformed file should produce a visible error without destroying other collections.

Test same-directory replacement on Windows, including replacement of an existing file and startup handling of leftover temporary/backup files. Do not delete the only valid copy before its replacement is available. Individual file replacement does not make several files transactional.

Support one application writer to the storage root. A second application instance must not mutate the same files; use a small exclusive lock rather than designing multi-process synchronization. Serialize collection mutations and reject conflicting import/remove/reindex actions with a clear busy state.

### Import sequence

1. Select PDFs and process them sequentially for the collection.
2. Copy each PDF into a temporary file in the collection and hash the managed bytes. Check for a duplicate hash within that collection, then promote the copy to its final ID-based filename.
3. Immediately create document metadata with `status: processing` so the import is visible and recoverable.
4. Extract pages and chunks. Reserve vector IDs and save the IDs/chunks before any vector insert.
5. Generate embeddings in bounded batches. Report stages and completed chunk counts. Keep successful batches in memory during this import; a failed attempt may need re-embedding on Retry.
6. Acquire the collection mutation section. Save `index/state.json` as dirty with `{operation: import, documentId: ...}` before the first native mutation. Pause search against that index while committing.
7. Insert the vectors and write the complete native snapshot through a temporary sibling.
8. Save the document as ready, then save index state as clean with its profile and count.
9. Release the mutation section, refresh collection state, and report success.

Stop during extraction/embedding leaves a failed/interrupted document that can be retried. If the short local commit has already begun, finish or roll it back before reporting cancellation; never abandon it between writes.

### Startup recovery

- Processing documents with no active operation become failed/interrupted and remain visible for Retry.
- For a dirty import, use the saved document's vector IDs to remove any partly committed entries, save the corrected snapshot, mark the document interrupted, and only then mark the index clean. Removal must tolerate IDs absent from an older snapshot.
- For a dirty removal, finish the recorded removal using remaining metadata. If metadata has already gone, the prescribed save order means vector removal has already been persisted; finish local cleanup before clearing the checkpoint.
- If an index cannot load, has an incompatible profile, or cannot be reconciled safely, mark it as needing re-indexing and disable search. Keep PDFs and chats readable. Do not silently restore a stale snapshot and claim it is current.
- Leftover managed PDFs without metadata are shown as interrupted imports that can be retried or removed. Never silently delete them.

### Removal and re-indexing

For PDF removal, record a dirty removal, mark the document deleting, remove its vectors and save the snapshot, close any viewer handle, remove the managed PDF and metadata, then mark the index clean. An OS file-lock failure remains visible and retryable.

Existing chats keep their citation snapshots and show “PDF removed” when appropriate. Deleting a collection requires an explicit UI confirmation explaining that its PDFs and chats are included.

For a full re-index, disable search, set the index state to needing re-indexing, update the collection profile if requested, and build a fresh index using the same extraction/embedding/insertion helpers. Keep the checkpoint in that state throughout the rebuild; per-document helpers must not publish a clean index. Save the final snapshot and compatible document statuses before marking it clean. Re-enable search only when the index is consistent and the remaining failed documents are clearly excluded. An interrupted full rebuild remains visibly resumable/retryable rather than entering normal import recovery. Warn that this operation requires embedding requests; do not trigger it automatically when settings change.

## 9. Retrieval and evidence formatting

Use one function with explicit concrete dependencies:

```dart
Future<List<PaperChunk>> retrieve(
  String collectionId,
  String query, {
  required LocalStorage storage,
  required EmbeddingClient embeddings,
  required CollectionIndex index,
  int topK = 15,
  int finalLimit = 8,
});
```

The steps are: embed the query with the collection profile, search the active index, map IDs to chunks, discard duplicates or strongly overlapping passages, and retain up to eight within a conservative evidence budget. Return fewer if fewer are available. Do not pad weak evidence to satisfy a quota.

Do not add adjacent chunks automatically in the initial version; `read_page` provides additional context when requested. Do not invent a universal cosine threshold before evaluating representative questions.

Assign source IDs only after evidence selection:

```text
[S1]
Paper: HippoRAG
PDF page: 5
Section: Retrieval
Text: <exact extracted passage>
```

The application owns every source ID and citation record. Source numbering is stable and monotonically increasing within an answer, including additional tool results. Never recycle a source ID when trimming context.

## 10. One research agent and one streaming loop

Construct `ChatOpenAI` inside `research_agent.dart` with the selected model, API key, and `https://openrouter.ai/api/v1`. Verify that the chosen model/provider supports streaming and tools. Optional attribution headers do not require an application website or backend.

Start each paper question with one `search_papers` retrieval. Supply recent conversation context so the model can interpret follow-up questions and request a more specific search when needed. Do not add a separate query-rewriting model.

Expose only these read tools:

| Tool | Result |
| --- | --- |
| `search_papers(query)` | Bounded evidence blocks from the current collection |
| `read_page(documentId, page)` | Bounded passages from that paper's page, using the same source/citation format |
| `list_papers()` | Local IDs, titles, and availability status |

Use saved page chunks for `read_page` where sufficient, or extract the managed PDF page on demand. Validate collection membership and page bounds in code. All returned evidence receives application-generated source metadata; page reads must be citable too.

The loop is:

```text
Prepare initial evidence and source map
→ request a streamed model response
→ concatenate LangChain result chunks
→ publish visible text and tool status
→ if completed tool calls exist, validate and execute them
→ append the full assistant tool-call message and matching tool results
→ continue the same loop
→ finish when there are no tool calls
```

Execute tools only after their arguments are complete and valid. Use LangChain's concatenation facilities rather than parsing partial JSON yourself. Preserve provider-specific message blocks in the active tool transcript. Keep reasoning/internal blocks out of the visible answer.

Budgets apply to the entire user turn: at most four tool executions including initial retrieval, at most four model requests, and tools disabled on the final allowed model request or when the tool budget is exhausted. Count every tool in a multi-tool response. Return bounded error results for rejected calls rather than executing beyond the limit.

Start with up to eight evidence blocks, approximately 6,000 evidence tokens, a bounded recent-history window, and an explicit output limit. Treat these as tunable ceilings and fit the whole request below the selected model's context limit. Include tool results and any retained prior excerpts in the same budget.

Prompt the model to cite research claims beside the relevant sentences, distinguish inference from paper claims, and say when evidence is insufficient. Document text is untrusted evidence, not instructions. Tool dispatch is a fixed switch over the three names; model output cannot initiate writes or supply executable file paths.

## 11. Streaming, cancellation, and chat saves

Use `Stream<ChatEvent>` with five small variants:

```text
ToolStatus(message)
SourcesUpdated(sourceMap)
TextChunk(text)
ChatDone()
ChatError(error)
```

`SourcesUpdated` publishes application-owned mappings before any text that can cite them. This supports clickable citations while the response is streaming without an event bus.

`ChatController` owns the current assistant buffer and its subscription. `ResearchAgent` owns the request-scoped network resources and exposes a direct cancellation method. Wire subscription cancellation to the same cleanup path. Keep import network clients separate from generation clients.

The chat sequence is:

1. Save the user message before generation starts. If saving fails, report it before starting a paid request.
2. Create an in-memory assistant message and a unique generation ID bound to the chat and collection.
3. Start the agent, accumulate text, and update source mappings.
4. Throttle rendering to a modest interval such as 40–60 ms. Rebuild the active message, not the whole sidebar and history.
5. On normal completion, validate citation references and save the assistant once as complete.
6. On Stop or failure, save the visible partial answer once as cancelled or failed. Do not automatically continue a partially streamed answer after an error.

Stop sets the cancellation flag immediately, cancels the request through the supported transport path, cancels the subscription, and prevents new model/tool calls. Check cancellation at awaited boundaries. Ignore late callbacks using the generation ID. Verify cancellation behavior against the chosen HTTP/LangChain versions; dropping the UI subscription alone is insufficient.

Permit one active generation in V1. Stop and finalize it before switching to another active chat/collection or deleting its source documents. Closing the app should attempt the same cleanup. An abrupt process termination can lose text generated since the last chat save; do not promise token-level crash recovery.

If the final disk write fails, keep the response visible with an unsaved indicator and Retry save. Do not report it as persisted.

## 12. Source inspection and citation correctness

Inline citations are application-owned links. Resolve them using `(messageId, sourceId)`, never a global map. Parse citation markers in ordinary message text, excluding code spans and fenced code; do not apply a blind replacement to raw Markdown. Unknown IDs remain visibly unresolved and unlinked.

Clicking a valid citation opens `SourcePanel` with the saved title, filename, section, physical page, and exact evidence excerpt. The panel can expand the passage and open the original managed PDF at that page. Render the PDF in the same side area while keeping the conversation visible. Highlight the source passage when the location can be verified.

On PDF navigation, derive the file path locally and verify its identity. Use the recorded source range with compatible extraction data. If offsets no longer match, locate the exact saved excerpt on that page; handle ambiguous matches conservatively. If the passage cannot be located precisely, open the verified page and show the saved excerpt without claiming an exact highlight. A hash mismatch must be reported as a changed file.

Store citation excerpts with the answer independently of index metadata. Re-indexing must not rewrite old source snapshots. A removed document keeps its excerpt available but disables PDF navigation. The answer's source list contains only citations actually used, and it shows multiple sources when a claim references more than one paper.

When previous evidence is included in a new model prompt, register its saved excerpts in the current answer's source map and rewrite the corresponding historical markers to those newly assigned IDs in the prompt copy only. Omit historical citation markers whose evidence is outside the context budget. Persisted messages are unchanged. Never let an earlier `[S1]` masquerade as an unrelated current `[S1]`.

A valid source mapping verifies provenance, not semantic entailment. Do not label citations as independently fact-checked. The source panel makes the model's use of evidence inspectable by the user.

Disable automatic remote image loading from assistant Markdown. External links, if supported, require an explicit user click; citation links always follow the local resolver.

## 13. Desktop UI scope

Build the first working flow with plain Flutter widgets, then apply the minimal desktop styling.

- Sidebar: New collection, expandable collections and chats, New chat, rename/delete menus, settings access.
- Collection view: document rows with title, import/index status, retry, remove, and open actions; one import-progress indicator.
- Chat view: selectable Markdown, inline citation chips, copy response, source list, bounded-width content, and clear empty/error states.
- Composer: Enter to send, Shift+Enter for newline, Send/Stop action, disabled send when the active operation cannot accept another message.
- Source panel: saved excerpt, paper/page identity, open/highlight in PDF, and explicit removed/changed-source states.
- Settings: API key, verified chat-model selection, default embedding configuration for new collections, theme, and local data location.

Use native window behavior initially. Avoid custom title bars, drag-and-drop, desktop menu frameworks, and elaborate animations until the citation flow is complete. Do not auto-scroll if the user has scrolled up to read earlier messages. Persisted text and citation inspection must work without a network connection.

## 14. Implementation milestones

| Milestone | Deliverable | Exit criteria |
| --- | --- | --- |
| 0. Dependency proof | Pinned package set, reproducible TurboVEC DLL, PDF and OpenRouter probes | Packaged Windows release loads PDF/native index; index survives restart/removal; text embeddings and streaming/tool calls work with the user's configured key |
| 1. Local foundation | Models, file helpers, collection creation, credential settings, basic shell | Rename does not change paths; existing JSON reloads; failed writes preserve the last valid object; a second writer is rejected |
| 2. Paper to evidence | Import function, PDF chunks, embeddings, index, retrieval | Imported PDF no longer depends on its source path; copied page text maps to returned chunks; failed imports are visible and retryable |
| 3. Complete citation flow | Agent, streaming, source map, source panel, page navigation, chat saves | Import one real paper, ask a factual question, inspect the supporting passage, restart, and reopen the same citation |
| 4. Collection operations and recovery | Multiple chats/papers, remove/delete/retry/reindex, cancellation | Interrupted commits recover; removed papers leave readable historical excerpts; Stop works during retrieval, tools, and streaming |
| 5. Desktop finish and release | Styling, keyboard behavior, error states, final package | Smooth interaction with representative collections; clean-machine packaging and full acceptance checks pass |

Milestone 3 is the first complete product demonstration. Do not postpone source inspection until after UI polish.

## 15. Verification and definition of done

Write focused tests around behavior that can lose data, misattribute evidence, or leave paid requests running. Use synthetic vectors for deterministic native tests and a small real-paper fixture set for extraction/retrieval evaluation. Live OpenRouter checks are opt-in with a configured key and never run automatically in ordinary tests.

Required checks:

- JSON round trips, missing/unsupported fields, malformed-object isolation, and Windows replacement failure recovery.
- Import fault injection after metadata creation, vector insertion, snapshot save, and ready-state save; restart recovery must never serve partly committed evidence.
- Deletion fault injection and locked-PDF handling, preserving historical citation snapshots.
- Native add/search/remove/save/reopen, duplicate/reused ID rejection, invalid dimensions, NaN/zero-vector rejection, and wrong-profile detection.
- Two-column text, multiple pages, Unicode ranges, overlapping chunks, captions, empty/scanned pages, and physical versus printed page numbering.
- Source maps from both search and page tools; citations from multiple papers; unknown IDs; repeated `[S1]` across messages; unchanged citations after re-indexing; removed/changed files.
- Streaming tool arguments split over multiple chunks, correct tool-result IDs, multi-tool responses, context limits, exhausted budgets, and error propagation.
- Stop during question embedding, a tool, and answer streaming; no additional calls or late text updates; partial message persisted once.
- Restart/offline reading and citation opening after the external original PDF has been moved or deleted.
- A small question set with expected supporting pages plus unanswerable questions; assess evidence coverage and inspect the actual cited passages. Do not rely on random-vector benchmarks as proof of research retrieval quality.
- `flutter analyze`, relevant Flutter tests, and a Windows release build with bundled native dependencies. Test outside the developer checkout so missing DLLs and absolute build paths are exposed.

V1 is complete when the requested collection/document/chat operations work, responses stream and stop reliably, and a user can inspect the exact saved evidence behind an answer and navigate to the managed PDF after restart. Any remaining extraction limitation or unavailable native integration must be explicit, not hidden behind a successful-looking UI.

## 16. Documentation used for planning

These references establish available APIs; the compatibility milestone must verify the exact pinned versions and provider route.

- [LangChain.dart OpenRouter integration](https://github.com/davidmigloz/langchain_dart/blob/main/docs/modules/model_io/models/chat_models/integrations/open_router.md)
- [LangChain streamed-result concatenation](https://github.com/davidmigloz/langchain_dart/blob/main/docs/expression_language/streaming.md)
- [LangChain tools and streaming tool calls](https://github.com/davidmigloz/langchain_dart/blob/main/docs/modules/model_io/models/chat_models/how_to/tools.md)
- [langchain_core tool API](https://pub.dev/documentation/langchain_core/latest/tools/)
- [OpenRouter embeddings endpoint](https://openrouter.ai/docs/api/api-reference/embeddings/create-embeddings)
- [Gemini Embedding 2 model capabilities](https://openrouter.ai/google/gemini-embedding-2)
- [pdfrx package and Windows requirements](https://pub.dev/packages/pdfrx)
- [pdfrx PDF page text, geometry, and numbering](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfPage-class.html)
- [saia_turbovec package and platform setup](https://pub.dev/packages/saia_turbovec)
- [TurboVecIndex Dart API](https://pub.dev/documentation/saia_turbovec/latest/domain_use_cases_turbovec_index/TurboVecIndex-class.html)
- [saia_turbovec native build provenance](https://github.com/Open-Neom/saia_turbovec/blob/main/native_provenance.json)
- [saia_turbovec Windows packaging](https://github.com/Open-Neom/saia_turbovec/blob/main/windows/CMakeLists.txt)
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
