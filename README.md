# ruby_llm-mongoid

[![CI](https://github.com/washu/ruby_llm-mongoid/actions/workflows/ci.yml/badge.svg)](https://github.com/washu/ruby_llm-mongoid/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/washu/ruby_llm-mongoid/badge.svg?branch=main)](https://coveralls.io/github/washu/ruby_llm-mongoid?branch=main)
[![Gem Version](https://img.shields.io/gem/v/ruby_llm-mongoid)](https://rubygems.org/gems/ruby_llm-mongoid)

Drop-in Mongoid persistence for [ruby_llm](https://github.com/crmne/ruby_llm). Use MongoDB as your Rails model layer instead of ActiveRecord — same `acts_as_chat` API, same feel.

## Requirements

- Ruby >= 3.3
- Mongoid >= 8.0
- ruby_llm >= 1.16

## Installation

Add to your Gemfile:

```ruby
gem "ruby_llm-mongoid"
```

## Quick start

### 1. Generate models

```bash
bin/rails g ruby_llm:mongoid:install
```

This creates four model files (`Chat`, `Message`, `ToolCall`, `LlmModel`) and `config/initializers/ruby_llm.rb`. No migrations — Mongoid is schemaless; fields are declared in the model files.

### 2. Create indexes

```bash
bin/rails db:mongoid:create_indexes
```

### 3. Configure API keys

Edit `config/initializers/ruby_llm.rb`:

```ruby
RubyLLM.configure do |config|
  config.openai_api_key    = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
```

### 4. Seed the model registry

```bash
bin/rails runner "LlmModel.save_to_database"
```

This populates MongoDB with the bundled model list so `Chat.create!(model: "gpt-4o-mini")` can resolve the model record.

### 5. Start chatting

```ruby
chat = Chat.create!(model: "gpt-4o-mini")
chat.ask("What is the capital of France?")
# => saves user + assistant messages to MongoDB
```

## Model setup

### Default (generated) layout

```ruby
class Chat
  include Mongoid::Document
  include Mongoid::Timestamps

  acts_as_chat model: :llm_model, model_class: "LlmModel"
end

class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :role,                  type: String
  field :content,               type: String
  field :input_tokens,          type: Integer
  field :output_tokens,         type: Integer
  # ...additional token/thinking fields

  acts_as_message model: :llm_model, model_class: "LlmModel"
end

class ToolCall
  include Mongoid::Document
  include Mongoid::Timestamps

  field :tool_call_id,  type: String
  field :name,          type: String
  field :arguments,     type: Hash, default: {}

  acts_as_tool_call
end

class LlmModel
  include Mongoid::Document
  include Mongoid::Timestamps

  field :model_id,  type: String
  field :name,      type: String
  field :provider,  type: String
  # ...pricing/capability fields

  acts_as_model
end
```

### Custom class / association names

```ruby
class Conversation
  include Mongoid::Document

  acts_as_chat messages: :turns,
               message_class: "Turn",
               model: :ai_model,
               model_class: "AiModel"
end
```

## API reference

### Chat

```ruby
chat = Chat.create!(model: "gpt-4o-mini")
chat = Chat.create!(model: "claude-opus-4-7", provider: "anthropic")

chat.ask("Hello!")
chat.say("Hello!")    # alias for ask

chat.with_instructions("You are a helpful assistant.")
chat.with_instructions("More context.", append: true)
chat.with_runtime_instructions("Only reply in French.")  # not persisted to DB

chat.with_model("claude-opus-4-7")
chat.with_tool(MyTool)
chat.with_tools(ToolA, ToolB)
chat.with_temperature(0.7)
chat.with_thinking(budget: 5000)

chat.on_new_message  { |msg| puts msg.content }
chat.on_end_message  { |msg| broadcast(msg) }

chat.cost  # => RubyLLM::Cost
```

### Message

```ruby
msg = chat.messages_association.last
msg.to_llm          # => RubyLLM::Message
msg.tokens          # => RubyLLM::Tokens
msg.cost            # => RubyLLM::Cost
msg.to_partial_path # => "messages/assistant"
```

### Model registry

`acts_as_model` automatically registers a `MongoidSource` with `RubyLLM.config.model_registry_source`, so `RubyLLM.models` reads from MongoDB on boot instead of the bundled JSON file.

```ruby
LlmModel.save_to_database  # seed MongoDB from the bundled model registry (run once after install)
LlmModel.refresh!          # fetch the latest list from all providers, then persist to MongoDB
```

Both methods are idempotent — `refresh!` is a good candidate for a periodic background job or a deploy hook.

## Differences from ActiveRecord integration

| Concern | ActiveRecord | Mongoid (this gem) |
|---|---|---|
| Primary key type | integer | BSON::ObjectId |
| Tool-call result FK field | `tool_call_id` (integer) | `parent_tool_call_id` (ObjectId) |
| Transactions | native | requires replica set; auto no-op on standalone |
| File attachments | ActiveStorage | GridFS via `GridFsAttachment` concern |
| `has_many :through` | supported | replaced by direct queries |

### `parent_tool_call_id` field name

In the ActiveRecord integration the FK column linking a tool-result message back to its ToolCall is named `tool_call_id` (integer). Mongoid uses `parent_tool_call_id` (BSON::ObjectId) to avoid a type collision with the string `tool_call_id` field that stores the provider-issued call ID. This is handled automatically — you don't need to think about it unless you are writing raw queries.

## Transactions

Multi-document transactions require a MongoDB **replica set** or Atlas cluster. On a standalone `mongod` the transaction helper automatically falls back to running the block without a transaction — useful for development and testing.

For production, run at minimum a single-node replica set:

```bash
# mongod.conf: add replication.replSetName: "rs0"
mongosh --eval "rs.initiate()"
```

## File attachments (GridFS)

Include `RubyLLM::Mongoid::GridFsAttachment` in your message model to store attachments in MongoDB's native GridFS bucket instead of ActiveStorage:

```ruby
class Message
  include Mongoid::Document
  include Mongoid::Timestamps
  include RubyLLM::Mongoid::GridFsAttachment

  field :role,    type: String
  field :content, type: String
  # ...other fields

  acts_as_message model: :llm_model, model_class: "LlmModel"
end
```

Then pass files to `ask` the same way you would with the ActiveRecord integration:

```ruby
chat.ask("What's in this image?", with: [params[:file]])
chat.ask("Summarise this PDF.",    with: ["/path/to/doc.pdf"])
```

Files are stored in a GridFS bucket named `"attachments"` by default. Change it per model:

```ruby
class Message
  include RubyLLM::Mongoid::GridFsAttachment
  use_gridfs_bucket :llm_files
end
```

GridFS files are automatically deleted when the owning message or its parent chat is destroyed.

## Testing

```bash
bundle exec rspec
```

The spec_helper checks whether MongoDB is reachable on `localhost:27017`. If nothing is listening it starts a `mongo:8.0` Docker container automatically and stops it when the suite exits. You don't need to start MongoDB manually.

The suite uses `database_cleaner-mongoid` for collection-level isolation between examples. LLM HTTP calls are stubbed with WebMock — no real API keys required.

## Contributing

Bug reports and pull requests welcome at [github.com/SalScotto/ruby_llm-mongoid](https://github.com/SalScotto/ruby_llm-mongoid).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
