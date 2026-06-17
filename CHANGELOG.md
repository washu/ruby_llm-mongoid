## [Unreleased]

## [0.1.0] - 2026-06-17

### Added

- `acts_as_chat` macro — persists chat sessions to MongoDB with full parity to ruby_llm's ActiveRecord integration
- `acts_as_message` macro — persists messages with role, content, token counts, thinking fields, and tool-call associations
- `acts_as_tool_call` macro — persists provider-issued tool calls and links result messages via `parent_tool_call_id`
- `acts_as_model` macro — persists LLM model registry records; supports `refresh!` and `save_to_database`
- `RubyLLM::Mongoid::MongoidSource` — plugs into `RubyLLM.config.model_registry_source` for Mongoid-backed model registry
- `RubyLLM::Mongoid::Transaction` — wraps blocks in multi-document transactions with automatic fallback for standalone mongod
- `bin/rails g ruby_llm:mongoid:install` generator — creates model files with field declarations (no migrations needed)
- SimpleCov with ≥ 90% line and ≥ 50% branch coverage enforced on every CI run
- `RubyLLM::Mongoid::GridFsAttachment` concern — opt-in GridFS-backed file attachments with automatic cleanup on message/chat destroy
- Full RSpec suite against a real MongoDB 8.0 instance; spec_helper auto-starts a Docker container if none is reachable
- GitHub Actions `ci.yml` — tests on Ruby 3.2–3.4 with MongoDB 8.0, separate RuboCop lint job, coverage artifact upload
- GitHub Actions `release.yml` — automated gem publishing on `v*.*.*` tags
