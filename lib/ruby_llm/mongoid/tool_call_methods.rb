# frozen_string_literal: true

require "active_support/concern"
require "ruby_llm/mongoid/payload_helpers"

module RubyLLM
  module Mongoid
    # Mixes into a Mongoid document that represents a persisted tool call.
    # Mirrors RubyLLM::ActiveRecord::ToolCallMethods.
    module ToolCallMethods
      extend ActiveSupport::Concern
      include PayloadHelpers

      def tool_error_message
        payload_error_message(arguments)
      end
    end
  end
end
