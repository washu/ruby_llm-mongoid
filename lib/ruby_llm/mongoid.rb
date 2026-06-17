# frozen_string_literal: true

require "ruby_llm"
require "mongoid"
require "active_support"
require_relative "mongoid/version"
require_relative "mongoid/payload_helpers"
require_relative "mongoid/transaction"
require_relative "mongoid/grid_fs_attachment"
require_relative "mongoid/model_methods"
require_relative "mongoid/tool_call_methods"
require_relative "mongoid/message_methods"
require_relative "mongoid/chat_methods"
require_relative "mongoid/acts_as"

module RubyLLM
  module Mongoid
    class Error < StandardError; end
  end
end

if defined?(Rails)
  require_relative "mongoid/railtie"
else
  # In non-Rails environments (tests, scripts) auto-install the macros
  # immediately after Mongoid is loaded.
  RubyLLM::Mongoid::ActsAs.install!
end
