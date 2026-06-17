# frozen_string_literal: true

# ─── LlmModel ────────────────────────────────────────────────────────────────

class LlmModel
  include Mongoid::Document
  include Mongoid::Timestamps

  field :model_id,           type: String
  field :name,               type: String
  field :provider,           type: String
  field :family,             type: String
  field :model_created_at,   type: Time
  field :context_window,     type: Integer
  field :max_output_tokens,  type: Integer
  field :knowledge_cutoff,   type: Date
  field :modalities,         type: Hash,  default: {}
  field :capabilities,       type: Array, default: []
  field :pricing,            type: Hash,  default: {}
  field :metadata,           type: Hash,  default: {}

  index({ provider: 1, model_id: 1 }, unique: true)

  acts_as_model
end

# ─── ToolCall ─────────────────────────────────────────────────────────────────

class ToolCall
  include Mongoid::Document
  include Mongoid::Timestamps

  field :tool_call_id,      type: String
  field :name,              type: String
  field :arguments,         type: Hash, default: {}
  field :thought_signature, type: String

  index({ tool_call_id: 1 }, unique: true)

  acts_as_tool_call
end

# ─── Message ──────────────────────────────────────────────────────────────────

class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :role,                  type: String
  field :content,               type: String
  field :content_raw,           type: Hash
  field :thinking_text,         type: String
  field :thinking_signature,    type: String
  field :thinking_tokens,       type: Integer
  field :input_tokens,          type: Integer
  field :output_tokens,         type: Integer
  field :cached_tokens,         type: Integer
  field :cache_creation_tokens, type: Integer

  index({ role: 1 })
  index({ created_at: 1 })

  acts_as_message model: :llm_model, model_class: "LlmModel"
end

# ─── Chat ─────────────────────────────────────────────────────────────────────

class Chat
  include Mongoid::Document
  include Mongoid::Timestamps

  acts_as_chat model: :llm_model, model_class: "LlmModel"
end

# ─── GridFsMessage / GridFsChat ───────────────────────────────────────────────
# Message model that opts into GridFS-backed file attachments.

class GridFsMessage
  include Mongoid::Document
  include Mongoid::Timestamps
  include RubyLLM::Mongoid::GridFsAttachment

  field :role,         type: String
  field :content,      type: String
  field :content_raw,  type: Hash
  field :input_tokens, type: Integer
  field :output_tokens, type: Integer

  acts_as_message chat: :chat, chat_class: "GridFsChat",
                  tool_calls: :tool_calls, tool_call_class: "ToolCall",
                  model: :llm_model, model_class: "LlmModel"
end

class GridFsChat
  include Mongoid::Document
  include Mongoid::Timestamps

  acts_as_chat messages: :grid_fs_messages, message_class: "GridFsMessage",
               model: :llm_model, model_class: "LlmModel"
end

# ─── MinimalMessage / MinimalChat ─────────────────────────────────────────────
# Message model with only the required fields — exercises field_declared? false
# branches in message_methods and chat_methods.

class MinimalMessage
  include Mongoid::Document
  include Mongoid::Timestamps

  field :role,    type: String
  field :content, type: String

  acts_as_message chat: :chat, chat_class: "MinimalChat",
                  tool_calls: :tool_calls, tool_call_class: "ToolCall",
                  model: :llm_model, model_class: "LlmModel"
end

class MinimalChat
  include Mongoid::Document
  include Mongoid::Timestamps

  acts_as_chat messages: :minimal_messages, message_class: "MinimalMessage",
               model: :llm_model, model_class: "LlmModel"
end
