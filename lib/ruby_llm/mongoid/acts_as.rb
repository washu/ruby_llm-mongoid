# frozen_string_literal: true

require "active_support/concern"
require "active_support/inflector"
require "ruby_llm/mongoid/chat_methods"
require "ruby_llm/mongoid/message_methods"
require "ruby_llm/mongoid/tool_call_methods"
require "ruby_llm/mongoid/model_methods"

module RubyLLM
  module Mongoid
    # Provides acts_as_chat, acts_as_message, acts_as_tool_call, and acts_as_model
    # class macros for Mongoid documents. Include this module (or let the Railtie do it)
    # and call the appropriate macro inside your document class.
    module ActsAs
      extend ActiveSupport::Concern

      def self.included(base)
        super
        RubyLLM.config.model_registry_source ||= RubyLLM::Mongoid::MongoidSource.new
      end

      @@install_lock = Mutex.new

      # Hook executed when a class does `include Mongoid::Document`.
      # Injects our class-method macros onto every Mongoid document automatically
      # so users don't have to `include RubyLLM::Mongoid::ActsAs` explicitly.
      def self.install!
        return unless defined?(::Mongoid::Document)

        @@install_lock.synchronize do
          return if ::Mongoid::Document.respond_to?(:acts_as_chat)

          ::Mongoid::Document.module_eval do
            include RubyLLM::Mongoid::ActsAs
          end
        end
      end

      class_methods do # rubocop:disable Metrics/BlockLength
        # -----------------------------------------------------------------------
        # acts_as_chat
        # -----------------------------------------------------------------------
        def acts_as_chat(messages: :messages, message_class: nil,
                         model: :model, model_class: nil)
          include RubyLLM::Mongoid::ChatMethods

          class_attribute :messages_association_name, :model_association_name,
                          :message_class, :model_class

          self.messages_association_name = messages
          self.model_association_name    = model
          self.message_class             = (message_class || messages.to_s.classify).to_s
          self.model_class               = (model_class || model.to_s.classify).to_s

          has_many messages,
                   class_name: self.message_class,
                   dependent: :destroy,
                   order: :created_at.asc

          belongs_to model,
                     class_name: self.model_class,
                     optional: true

          define_method(:messages_association) { send(messages_association_name) }
          define_method(:model_association)    { send(model_association_name) }
          define_method(:"model_association=") { |v| send(:"#{model_association_name}=", v) }
        end

        # -----------------------------------------------------------------------
        # acts_as_model
        # -----------------------------------------------------------------------
        def acts_as_model(chats: :chats, chat_class: nil)
          include RubyLLM::Mongoid::ModelMethods

          class_attribute :chats_association_name, :chat_class

          self.chats_association_name = chats
          self.chat_class             = (chat_class || chats.to_s.classify).to_s

          validates :model_id, presence: true
          validates :provider, presence: true
          validates :name,     presence: true
          validates :model_id, uniqueness: { scope: :provider }

          has_many chats, class_name: self.chat_class

          define_method(:chats_association) { send(chats_association_name) }
        end

        # -----------------------------------------------------------------------
        # acts_as_message
        # -----------------------------------------------------------------------
        def acts_as_message(chat: :chat, chat_class: nil, touch_chat: false, # rubocop:disable Metrics/ParameterLists
                            tool_calls: :tool_calls, tool_call_class: nil,
                            model: :model, model_class: nil)
          include RubyLLM::Mongoid::MessageMethods

          class_attribute :chat_association_name, :tool_calls_association_name,
                          :model_association_name, :chat_class, :tool_call_class,
                          :model_class

          self.chat_association_name       = chat
          self.tool_calls_association_name = tool_calls
          self.model_association_name      = model
          self.chat_class                  = (chat_class || chat.to_s.classify).to_s
          self.tool_call_class             = (tool_call_class || tool_calls.to_s.classify).to_s
          self.model_class                 = (model_class || model.to_s.classify).to_s

          belongs_to chat,
                     class_name: self.chat_class,
                     touch: touch_chat

          has_many tool_calls,
                   class_name: self.tool_call_class,
                   dependent: :destroy

          # parent_tool_call links a tool-result message back to the ToolCall doc
          # that produced the call.  We use a named field `parent_tool_call_id`
          # (BSON::ObjectId) rather than the string `tool_call_id` field to avoid
          # a type collision.
          belongs_to :parent_tool_call,
                     class_name: self.tool_call_class,
                     optional: true

          belongs_to model,
                     class_name: self.model_class,
                     optional: true

          delegate :tool_call?, :tool_result?, to: :to_llm

          define_method(:chat_association)       { send(chat_association_name) }
          define_method(:tool_calls_association) { send(tool_calls_association_name) }
          define_method(:model_association)      { send(model_association_name) }
        end

        # -----------------------------------------------------------------------
        # acts_as_tool_call
        # -----------------------------------------------------------------------
        def acts_as_tool_call(message: :message, message_class: nil,
                              result: :result, result_class: nil)
          include RubyLLM::Mongoid::ToolCallMethods

          class_attribute :message_association_name, :result_association_name,
                          :message_class, :result_class

          self.message_association_name = message
          self.result_association_name  = result
          self.message_class            = (message_class || message.to_s.classify).to_s
          self.result_class             = (result_class || self.message_class).to_s

          belongs_to message,
                     class_name: self.message_class

          has_one result,
                  class_name: self.result_class,
                  foreign_key: :parent_tool_call_id,
                  dependent: :nullify

          define_method(:message_association) { send(message_association_name) }
          define_method(:result_association)  { send(result_association_name) }
        end
      end
    end

    # ---------------------------------------------------------------------------
    # Model registry source — plugs into RubyLLM.config.model_registry_source
    # ---------------------------------------------------------------------------
    class MongoidSource
      def read
        model_class = resolve_model_class
        return [] unless model_class.respond_to?(:all)

        model_class.all.map(&:to_llm)
      rescue StandardError => e
        RubyLLM.logger.debug { "Failed to load models from MongoDB: #{e.message}, falling back to JSON" }
        []
      end

      private

      def resolve_model_class
        klass = RubyLLM.config.model_registry_class
        return klass unless klass.is_a?(String)

        klass.split("::").inject(Object) { |scope, name| scope.const_get(name) }
      end
    end
  end
end
