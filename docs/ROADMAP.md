# Code Editor Feature Roadmap

User-approved product direction, received 2026-10-27. This is the implementation
backlog, not a list of shipped capabilities. See FEATURES.md for implemented work
and RELEASE_READINESS.md for verified behavior and unresolved failures.

## Goal and product pillars

Build a fast, modern, developer-focused editor with first-class codebase
understanding, navigation, security, version history, and project exploration.
Optional AI enhances these tools; the editor remains useful without AI or a
collection of required extensions.

- **CODE:** editing, terminals, debugging, builds, testing.
- **EXPLORE:** symbols, architecture, dependencies, maps, call graphs.
- **HISTORY:** Git, local history, timelines, workspace snapshots.
- **SECURITY:** secrets, risky APIs, dependencies, findings, data-flow inspection.
- **INTELLIGENCE:** local AI, semantic search, project explanation, contextual help.

## Non-negotiable architecture

Project files → parser/AST → symbol/reference index → dependency/call graph →
semantic index → local AI context engine → developer.

Deterministic parsers, language servers, static analysis, Git and indexes power
core features. AI reasons over structured evidence and relevant retrieved source;
it must not replace those systems or blindly consume entire repositories.

Processing is local by default. Cloud AI is optional and explicitly configurable.
Every AI operation identifies local versus remote processing. Source must never
be uploaded merely because indexing, navigation, search, or security is enabled.
Network AI can be disabled completely. Core features remain usable with AI off.
Responsiveness, bounded resource use, cancellation, privacy exclusions and clear
analysis limits are acceptance criteria, not later polish.

## Existing foundation and current limits

- Native editor, Explorer, Stem terminal, Git account and basic repository actions.
- Shared toolbar search for files, commands, declarations, lines and literal text.
  These are lexical providers; semantic/reference/type search is not yet shipped.
- File Info: local filename/source inference, purpose evidence, imports and
  declarations from the active buffer. This is not AST or whole-project analysis.
- VSIX package import/removal exists; VS Code extension API execution does not.
- Workspaces and recovery exist; full snapshots and durable local timelines do not.
- Full native test suite still fails the Back canonical-file-identity assertion.
  Resolve before declaring the current navigation milestone release-ready.

## 1. Local AI Codebase Intelligence — CRITICAL

Index the entire workspace and update incrementally when files change. Model files,
classes, functions, methods, interfaces, imports, dependencies, variables, types,
configuration and tests. Support whole-codebase questions with local processing
preferred and no mandatory cloud upload. Optional cloud providers must be explicit.

Build relevant query context from AST/LSP information, symbols, references, imports,
call relationships, Git metadata, project structure, documentation, configuration,
dependency metadata and search results. Retrieve relevant portions, not the whole
repository. Keep evidence linked to its file and symbol.

Required question families include authentication locations, callers, class
explanations, variable writes, database-related code, user-input entry points,
credential storage, module dependents, removal impact, startup flow, similar
implementations and API endpoint consumers.

## 2. Semantic Project Search — CRITICAL

Unify literal text, regex, symbols, semantic meaning, file names, types, functions,
references and dependencies. Rank results and explain why each matched. Local
semantic search should not require cloud AI. An “authentication token validation”
query should find relevant validators, JWT verification and session refresh code,
including code that does not repeat those exact words.

## 3. Project X-Ray — HIGH

Provide a navigable architecture view of modules, classes, interfaces, functions,
dependencies, imports, calls and data flows. Selected items expose **Depends On**,
**Used By**, **Calls**, **Called By**, **Defined In** and **Referenced By** with links
to source. Distinguish proven semantic relationships from inferred ones.

## 4. Call Graph Visualization

Navigate execution relationships and open associated code. Follow callers/callees,
filter external libraries versus project code, collapse modules and search nodes.
Example: UI → DeleteCommand → FileService → PermissionCheck → Filesystem.

## 5. Explain This Project — HIGH

An unfamiliar repository can be explained through project purpose, entry points,
important modules, structure, data flow, external dependencies, security-sensitive
areas, test structure, build system, configuration and likely starting point.
Explanations link to files/symbols and use local codebase intelligence when present.
A deterministic overview must remain available without AI.

## 6. Time-Travel Editing — HIGH

Automatic persistent local file history beyond Undo/Redo and Git commits. Label
manual edits, AI refactors, renames, checkouts and opens when identifiable. Browse
and preview versions, compare revisions, restore safely, copy old code and create
a Git branch from an earlier state. Define retention/storage limits and protect
unsaved work during restoration.

## 7. Workspace Snapshots — HIGH

Named development contexts restore open files, cursor positions, selections,
terminal sessions and working directories, breakpoints/debug configuration, Git
branch, expanded folders, search results, active panels and Project X-Ray state.
A terminal process cannot be assumed restorable: report which state was restored
and which sessions need restarting. Branch changes must preserve unsaved work.

## 8. Code Archaeology

“Why Does This Exist?” combines Git blame, commit messages, related changes,
authors, files changed together, symbol/file history, references and related
commits. Investigate history inside the editor, with source links and evidence.

## 9. Native Security Intelligence — CRITICAL

A dedicated Security panel covers secrets/credentials, dangerous APIs, file
permissions, network endpoints, vulnerable dependencies, cryptography,
authentication/authorization, unsafe deserialization, command execution and
sensitive filesystem operations. Every finding has file, line, severity, reason,
relevant symbol and suitable remediation. Prefer high-confidence actionable
findings; avoid flooding users with speculative warnings. Do not display complete
secret values in lists or logs. Local checks work without AI.

## 10. Security / Data Flow Map

Trace data from user input, files, networks/APIs, environment and configuration to
databases, filesystem writes, shell execution, network requests, credential
storage and cryptographic operations. Visualize relevant transformations and
source/sink evidence. Label incomplete or inferred flows accurately.

## 11. Dependency Intelligence

For each dependency show declaration, imports, consuming modules, possible unused
status, available version metadata and relationships. “Why Is This Dependency
Installed?” traces it back to code that uses it. Dynamic imports and build-only
uses must prevent unsupported claims that a dependency is safe to remove.

## 12. First-Class Git Experience

Native branch management, commit browser, file/line history, blame, staging,
interactive diff, commit/branch comparison, merge tools and conflict resolution.
Build on existing Git actions instead of duplicating repository state machinery.

## 13. Advanced Diff and Merge Workspace

Two-way diff, three-way merge, inline and side-by-side views, character changes,
conflict navigation, choose left/right/both and manual editing. Merging is a
workspace, not a basic text dump. Preserve input versions and support undo.

## 14. Integrated Database Explorer

Modular providers, initially considering SQLite, PostgreSQL and MySQL. Browse
databases/tables, inspect schemas, execute and save queries, view results and
link source usage where possible. Separate connection secrets from project files.

## 15. Integrated HTTP / API Client

GET, POST, PUT, PATCH, DELETE; headers, query parameters, authentication, JSON bodies
and response inspection. Save requests in projects and link discovered endpoints
where possible. Sending a request is explicit; opening a project never sends it.

## 16. Persistent Code Bookmarks

Named locations with notes, categories, colors and project persistence. Follow
symbols when practical; use line anchors as fallback and identify stale anchors.
Examples: authentication entry, database initialization, archive extraction,
investigate later.

## 17. Scratch Files

Temporary programming files outside Git, syntax highlighting, automatic local
save, optional execution with an available runtime, and promotion to a normal
project file. Execution remains explicit and respects edition capabilities.

## 18. Regex Builder and Tester

Pattern editor, test text, match highlighting, capture groups, replacement preview,
explanation, and insertion into source/search. Bound work and support cancellation
so pathological expressions cannot freeze the editor.

## 19. Terminal History Intelligence

Search commands, output, errors and working directories; locate earlier failed
builds and explicitly rerun commands. Retention and exclusions must account for
credentials or sensitive output. Never rerun a command merely by selecting it.

## 20. Universal Symbol Navigation

One navigation surface for files, classes, functions, methods, variables,
interfaces, types, commands, settings, bookmarks and dependencies, with prefixes or
filters for symbols, commands, lines and security findings. Keep the existing
shared macOS Cmd+P field; finalize additional syntax during implementation.

## 21. Editor Performance Inspector

Expose memory/CPU, indexing, language server performance, AI activity, plugin
performance and file watcher activity so users can answer “Why is my editor slow?”
Distinguish measured values from unavailable metrics; inspector overhead is bounded.

## 22. Native Remote Development

Design a workspace-service boundary supporting SSH, containers, WSL and remote
Linux with a near-local experience. Keep filesystem, execution, indexing and
credentials on the correct side of that boundary. Local editing remains usable
without a remote agent.

## 23. Integrated Hex / Binary Viewer

Hex and ASCII views, offsets, search, byte selection and basic binary comparison
for security work, systems development, format debugging and reverse engineering.
Read large files in bounded chunks. Inspection must never execute file contents.

## 24. Privacy Dashboard

Show local index, embeddings, local model and project history separately from
cloud providers, transmitted data and active remote requests. Provide a complete
network-AI off switch. Developers can always determine whether source is leaving
the machine. Local search/indexing must not require provider configuration.

## 25. Extension Philosophy

Install editor → open repository → automatic project analysis → start coding.
Core workflow does not require dozens of plugins. Extensions enhance additional
languages, frameworks, specialized tools, themes, AI/database providers and debug
adapters. Preserve clear compatibility and activation status for imported VSIXs.

## Delivery sequence and acceptance gates

### A. Stabilize and establish local workspace intelligence

Finish File Info visual acceptance and fix existing navigation failures. Extract a
shared workspace service from duplicated lexical scans. Define stable file/symbol
identities, source locations, buffer/disk provenance, versions and relationship
records. Add bounded incremental indexing, cancellation, exclusions, file watching,
cache invalidation and a visible index status. Unsaved buffers take precedence.
No AI dependency or network traffic. Test edits, creates, renames, deletions,
symlinks, Unicode, stale results and large workspaces.

### B. Semantic navigation, security and privacy foundations

Introduce AST/LSP providers with labeled lexical fallbacks. Feed references,
imports and types to shared search, File Info and dependency views. Add native
security findings with confidence/severity and evidence, plus the Privacy panel.
Test that all these workflows operate with AI and network access disabled.

### C. Project exploration and optional local intelligence

Build Project X-Ray, call graphs, deterministic project explanations and scoped
local retrieval on the same index. Add optional embeddings/local model adapters
and grounded question answering. Display citations, incomplete coverage and local
versus remote operation. Cloud providers are opt-in and share only selected,
relevant context under the user's configured policy.

### D. History and development contexts

Local file history, snapshots, bookmarks, archaeology, Git history and advanced
merge workspace. Verify recoverability and unsaved-content protection before any
restore, checkout or conflict-resolution workflow.

### E. Specialized native tools and remote work

Scratch files, bounded regex tools, terminal history, binary viewer, HTTP client,
modular databases and remote workspace providers. Extend the performance/privacy
surfaces and extension interfaces as services ship.

Each milestone must include native regression checks, visual acceptance in the
installed app, documented limits, feature inventory updates and edition-specific
verification. A written roadmap entry is not an implemented feature.
