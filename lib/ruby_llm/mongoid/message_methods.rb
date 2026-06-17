# frozen_string_literal: true

require "active_support/concern"
require "ruby_llm/mongoid/payload_helpers"

module RubyLLM
  module Mongoid
    # Mixes into a Mongoid document that represents a persisted chat message.
    # Mirrors RubyLLM::ActiveRecord::MessageMethods but replaces AR-specific
    # introspection with Mongoid equivalents.
    module MessageMethods
      extend ActiveSupport::Concern
      include PayloadHelpers

      def to_llm
        RubyLLM::Message.new(
          role: role.to_sym,
          content: extract_content,
          thinking: thinking,
          tokens: tokens,
          tool_calls: extract_tool_calls,
          tool_call_id: extract_tool_call_id,
          model_id: model_association&.model_id
        )
      end

      def thinking
        RubyLLM::Thinking.build(
          text: field_value(:thinking_text),
          signature: field_value(:thinking_signature)
        )
      end

      def tokens
        RubyLLM::Tokens.build(
          input: field_value(:input_tokens),
          output: field_value(:output_tokens),
          cached: field_value(:cached_tokens),
          cache_creation: field_value(:cache_creation_tokens),
          thinking: field_value(:thinking_tokens)
        )
      end

      def cost
        RubyLLM::Cost.new(tokens: tokens, model: model_association)
      end

      def cache_read_tokens
        field_value(:cached_tokens)
      end

      def cache_write_tokens
        field_value(:cache_creation_tokens)
      end

      def to_partial_path
        partial_prefix = self.class.name.underscore.pluralize
        role_partial = if to_llm.tool_call?
                         "tool_calls"
                       elsif role.to_s == "tool"
                         "tool"
                       else
                         role.to_s.presence || "assistant"
                       end
        "#{partial_prefix}/#{role_partial}"
      end

      def tool_error_message
        payload_error_message(content)
      end

      private

      # Safely reads a field only if it is declared on this document class.
      def field_value(name)
        self.class.fields.key?(name.to_s) ? self[name] : nil
      end

      def extract_tool_calls
        tool_calls_association.to_h do |tc|
          [
            tc.tool_call_id,
            RubyLLM::ToolCall.new(
              id: tc.tool_call_id,
              name: tc.name,
              arguments: tc.arguments,
              thought_signature: tc.try(:thought_signature)
            )
          ]
        end
      end

      def extract_tool_call_id
        parent_tool_call&.tool_call_id
      end

      def extract_content
        return RubyLLM::Content::Raw.new(self[:content_raw]) if field_value(:content_raw).present?
        return gridfs_content(content) if respond_to?(:gridfs_file_ids) && gridfs_file_ids.present?

        content
      end
    end
  end
end
