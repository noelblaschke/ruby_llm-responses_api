# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-02-24

### Added

- **WebSocket mode** for lower-latency agentic workflows with persistent `wss://` connections
  - `RubyLLM::ResponsesAPI::WebSocket` standalone class
  - Streamed responses via `create_response` with block
  - Automatic `previous_response_id` chaining across turns
  - `warmup` for server-side model weight caching (`generate: false`)
  - Thread-safe with one-at-a-time response constraint
  - Supports all existing helpers: `State`, `Compaction`, `Tools`
  - Soft dependency on `websocket-client-simple` (lazy require with clear error)

## [0.3.1] - 2026-02-18

### Fixed

- Compatibility with RubyLLM v1.12.0 (`thinking:` parameter in `render_payload`)

## [0.3.0] - 2026-02-11

### Added

- **Shell tool** support for executing commands in hosted or local terminal environments
  - Auto-provisioned containers (`container_auto`), reusable containers (`container_reference`), and local execution (`local`)
  - Container networking with domain allowlists and domain-scoped secrets
  - Configurable memory limits (`1g`, `4g`, `16g`, `64g`)
  - `BuiltInTools.shell` helper and `parse_shell_call_results` parser
- **Server-side compaction** for multi-hour agent runs without hitting context limits
  - `Compaction.compaction_params(compact_threshold:)` helper
  - Pass via `chat.with_params(context_management: [{ type: 'compaction', compact_threshold: 200_000 }])`
- **Containers API** for managing persistent execution environments
  - `create_container`, `retrieve_container`, `delete_container`
  - `list_container_files`, `retrieve_container_file`, `retrieve_container_file_content`
- **Apply Patch tool** for structured diff-based file editing
  - `BuiltInTools.apply_patch` helper and `parse_apply_patch_results` parser

## [0.2.0] - 2026-01-15

### Added

- Legacy ActiveRecord support
- CI compatibility fixes

## [0.1.0] - 2025-01-03

### Added

- Initial release of the RubyLLM Responses API provider
- Core chat completion support with Responses API format
- Streaming support with typed event handling
- Function calling (tool use) support
- Built-in tools support:
  - Web Search (`web_search_preview`)
  - Code Interpreter (`code_interpreter`)
  - File Search (`file_search`)
  - Image Generation (`image_generation`)
  - MCP (Model Context Protocol) (`mcp`)
  - Computer Use (`computer_use_preview`)
- Stateful conversation support via `previous_response_id` and `store`
- Background mode for long-running tasks
- Response polling and cancellation
- Message extension to support `response_id`
- Model capabilities for GPT-4o, GPT-4.1, and O-series models
- Media handling for images, PDFs, and audio
