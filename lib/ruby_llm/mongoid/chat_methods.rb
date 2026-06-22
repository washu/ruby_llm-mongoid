# frozen_string_literal: true

require "active_support/concern"
require "ruby_llm/mongoid/transaction"

module RubyLLM
  module Mongoid
    # Mixes into a Mongoid document that represents a persisted chat session.
    # Mirrors RubyLLM::ActiveRecord::ChatMethods, replacing AR-specific persistence
    # and query calls with Mongoid equivalents.
    module ChatMethods
      extend ActiveSupport::Concern
      include Transaction

      included do
        before_save :resolve_model_from_strings
      end

      attr_accessor :assume_model_exists, :context

      # -------------------------------------------------------------------------
      # Model / provider assignment
      # -------------------------------------------------------------------------

      def model=(value)
        @model_string = value if value.is_a?(String)
        return if value.is_a?(String)

        if self.class.model_association_name == :model
          super
        else
          self.model_association = value
        end
      end

      def model_id=(value)
        if value.is_a?(String)
          @model_string = value
        else
          super
        end
      end

      def model_id
        model_association&.model_id
      end

      def provider=(value)
        @provider_string = value
      end

      def provider
        model_association&.provider
      end

      # -------------------------------------------------------------------------
      # Chat interface — mirrors the AR version
      # -------------------------------------------------------------------------

      def to_llm
        model_record = model_association
        @chat ||= (context || RubyLLM).chat(
          model: model_record.model_id,
          provider: model_record.provider.to_sym,
          assume_model_exists: assume_model_exists || false
        )
        @chat.reset_messages!

        ordered_messages = order_messages_for_llm(messages_association.to_a)
        ordered_messages.each { |msg| @chat.add_message(msg.to_llm) }
        reapply_runtime_instructions(@chat)

        setup_persistence_callbacks
      end

      def with_instructions(instructions, append: false, replace: nil)
        append = append_instructions?(append: append, replace: replace)
        persist_system_instruction(instructions, append: append)
        to_llm.with_instructions(instructions, append: append, replace: replace)
        self
      end

      def with_runtime_instructions(instructions, append: false, replace: nil)
        append = append_instructions?(append: append, replace: replace)
        store_runtime_instruction(instructions, append: append)
        to_llm.with_instructions(instructions, append: append, replace: replace)
        self
      end

      def with_tool(...)
        to_llm.with_tool(...)
        self
      end

      def with_tools(...)
        to_llm.with_tools(...)
        self
      end

      def with_model(model_name, provider: nil, assume_exists: false)
        self.model = model_name
        self.provider = provider if provider
        self.assume_model_exists = assume_exists
        resolve_model_from_strings
        save!
        to_llm.with_model(model_association.model_id, provider: model_association.provider.to_sym,
                                                      assume_exists: assume_exists)
        self
      end

      def with_temperature(...)
        to_llm.with_temperature(...)
        self
      end

      def with_thinking(...)
        to_llm.with_thinking(...)
        self
      end

      def with_params(...)
        to_llm.with_params(...)
        self
      end

      def with_headers(...)
        to_llm.with_headers(...)
        self
      end

      def with_schema(...)
        to_llm.with_schema(...)
        self
      end

      def on_new_message(&)
        to_llm.on_new_message(&)
        self
      end

      def on_end_message(&)
        to_llm.on_end_message(&)
        self
      end

      def before_message(...)
        to_llm.before_message(...)
        self
      end

      def after_message(...)
        to_llm.after_message(...)
        self
      end

      def before_tool_call(...)
        to_llm.before_tool_call(...)
        self
      end

      def after_tool_result(...)
        to_llm.after_tool_result(...)
        self
      end

      def on_tool_call(...)
        to_llm.on_tool_call(...)
        self
      end

      def on_tool_result(...)
        to_llm.on_tool_result(...)
        self
      end

      def add_message(message_or_attributes)
        llm_message = message_or_attributes.is_a?(RubyLLM::Message) ? message_or_attributes : RubyLLM::Message.new(message_or_attributes)
        content_text, attachments, content_raw = prepare_content_for_storage(llm_message.content)

        attrs = { role: llm_message.role, content: content_text }

        if llm_message.tool_call_id
          tc_db_id = find_tool_call_db_id(llm_message.tool_call_id)
          attrs[:parent_tool_call_id] = tc_db_id if tc_db_id
        end

        message_record = messages_association.create!(attrs)
        message_record.update!(content_raw: content_raw) if content_raw_field?(message_record)

        persist_content(message_record, attachments) if attachments.present?
        persist_tool_calls(llm_message.tool_calls, message_record: message_record) if llm_message.tool_calls.present?

        message_record
      end

      def cost
        RubyLLM::Cost.aggregate(messages_association.map(&:cost))
      end

      def create_user_message(content, with: nil)
        add_message(role: :user, content: build_content(content, with))
      end

      def ask(message = nil, with: nil, &)
        add_message(role: :user, content: build_content(message, with))
        complete(&)
      end

      alias say ask

      def complete(...)
        to_llm.complete(...)
      rescue RubyLLM::Error => e
        cleanup_failed_messages if @message&.persisted? && @message.content.blank?
        cleanup_orphaned_tool_results
        raise e
      end

      # -------------------------------------------------------------------------
      # Private implementation
      # -------------------------------------------------------------------------

      private

      def resolve_model_from_strings
        config = context&.config || RubyLLM.config
        @model_string ||= config.default_model unless model_association
        return unless @model_string

        model_info, _provider = RubyLLM::Models.resolve(
          @model_string,
          provider: @provider_string,
          assume_exists: assume_model_exists || false,
          config: config
        )

        model_klass = self.class.model_class.constantize
        model_record = model_klass.find_or_create_by!(
          model_id: model_info.id,
          provider: model_info.provider
        ) do |m|
          m.name     = model_info.name || model_info.id
          m.family   = model_info.family
          m.context_window    = model_info.context_window
          m.max_output_tokens = model_info.max_output_tokens
          m.capabilities      = model_info.capabilities || []
          m.modalities        = model_info.modalities.to_h
          m.pricing           = model_info.pricing.to_h
          m.metadata          = model_info.metadata || {}
        end

        self.model_association = model_record
        @model_string = nil
        @provider_string = nil
      end

      def setup_persistence_callbacks
        return @chat if @chat.instance_variable_get(:@_persistence_callbacks_setup)

        @chat.before_message { persist_new_message }
        @chat.after_message  { |msg| persist_message_completion(msg) }

        @chat.instance_variable_set(:@_persistence_callbacks_setup, true)
        @chat
      end

      def persist_new_message
        @message = messages_association.create!(role: :assistant, content: "")
      end

      def persist_message_completion(message)
        return unless message

        tool_call_db_id = find_tool_call_db_id(message.tool_call_id) if message.tool_call_id

        with_transaction do
          content_text, _attachments, content_raw = prepare_content_for_storage(message.content)

          attrs = {
            role: message.role,
            content: content_text
          }
          attrs[:input_tokens]           = message.input_tokens if field_declared?(@message, :input_tokens)
          attrs[:output_tokens]          = message.output_tokens if field_declared?(@message, :output_tokens)
          attrs[:cached_tokens]          = message.cached_tokens if field_declared?(@message, :cached_tokens)
          attrs[:cache_creation_tokens]  = message.cache_creation_tokens if field_declared?(@message,
                                                                                            :cache_creation_tokens)
          attrs[:thinking_text]          = message.thinking&.text if field_declared?(@message, :thinking_text)
          attrs[:thinking_signature]     = message.thinking&.signature if field_declared?(@message, :thinking_signature)
          attrs[:thinking_tokens]        = message.thinking_tokens if field_declared?(@message, :thinking_tokens)

          attrs[self.class.model_association_name] = model_association

          attrs[:parent_tool_call_id] = tool_call_db_id if tool_call_db_id

          @message.assign_attributes(attrs)
          @message.content_raw = content_raw if content_raw_field?(@message) && content_raw
          @message.save!

          persist_tool_calls(message.tool_calls) if message.tool_calls.present?
        end
      end

      def persist_tool_calls(tool_calls, message_record: @message)
        return if tool_calls.blank?

        supports_thought_signature = message_record.tool_calls_association.klass.fields.key?("thought_signature")

        tool_calls.each_value do |tc|
          attributes = tc.to_h
          attributes.delete(:thought_signature) unless supports_thought_signature
          attributes[:tool_call_id] = attributes.delete(:id)
          message_record.tool_calls_association.create!(**attributes)
        end
      end

      # Resolves a provider-issued tool_call_id string to the Mongo _id of the
      # ToolCall document. Done with two targeted queries instead of a SQL JOIN.
      def find_tool_call_db_id(tool_call_id)
        message_klass = messages_association.klass
        tc_assoc_name = message_klass.tool_calls_association_name
        tc_klass = message_klass.relations[tc_assoc_name.to_s].klass

        tc = tc_klass.where(tool_call_id: tool_call_id).first
        tc&.id
      end

      def cleanup_failed_messages
        RubyLLM.logger.warn "RubyLLM: API call failed, destroying message: #{@message.id}"
        @message.destroy
      end

      def cleanup_orphaned_tool_results
        last = messages_association.order_by(_id: :asc).last

        return unless last&.tool_call? || last&.tool_result?

        if last.tool_call?
          last.destroy
        elsif last.tool_result?
          tc_message = last.parent_tool_call.message_association
          tc_ids = tc_message.tool_calls_association.distinct(:_id)
          result_parent_ids = message_klass_for(last).where(
            parent_tool_call_id: { "$in" => tc_ids }
          ).distinct(:parent_tool_call_id)

          if tc_ids.sort != result_parent_ids.sort
            message_klass_for(last).where(parent_tool_call_id: { "$in" => tc_ids }).destroy_all
            tc_message.destroy
          end
        end
      end

      def message_klass_for(msg)
        msg.class
      end

      def persist_system_instruction(instructions, append:)
        with_transaction do
          if append
            messages_association.create!(role: :system, content: instructions)
          else
            replace_persisted_system_instructions(instructions)
          end
        end
      end

      def replace_persisted_system_instructions(instructions)
        system_messages = messages_association.where(role: :system).order_by(_id: :asc).to_a

        if system_messages.empty?
          messages_association.create!(role: :system, content: instructions)
          return
        end

        primary = system_messages.shift
        primary.update!(content: instructions) if primary.content != instructions
        system_messages.each(&:destroy)
      end

      def append_instructions?(append:, replace:)
        return append if replace.nil?

        append || (replace == false)
      end

      def order_messages_for_llm(messages)
        system_msgs, other_msgs = messages.partition { |m| m.role.to_s == "system" }
        system_msgs + other_msgs
      end

      def runtime_instructions
        @runtime_instructions ||= []
      end

      def store_runtime_instruction(instructions, append:)
        if append
          runtime_instructions << instructions
        else
          @runtime_instructions = [instructions]
        end
      end

      def reapply_runtime_instructions(chat)
        return if runtime_instructions.empty?

        first, *rest = runtime_instructions
        chat.with_instructions(first)
        rest.each { |instr| chat.with_instructions(instr, append: true) }
      end

      def build_content(message, attachments)
        return message if content_like?(message)

        RubyLLM::Content.new(message, attachments)
      end

      def content_like?(object)
        object.is_a?(RubyLLM::Content) || object.is_a?(RubyLLM::Content::Raw)
      end

      def prepare_content_for_storage(content)
        attachments  = nil
        content_raw  = nil
        content_text = content

        case content
        when RubyLLM::Content::Raw
          content_raw  = content.value
          content_text = nil
        when RubyLLM::Content
          attachments  = content.attachments.presence
          content_text = content.text
        when Hash, Array
          content_raw  = content
          content_text = nil
        end

        [content_text, attachments, content_raw]
      end

      def persist_content(message_record, attachments)
        return unless message_record.respond_to?(:gridfs_file_ids)

        ids = attachments.filter_map { |att| upload_to_gridfs(message_record, att) }
        message_record.push(gridfs_file_ids: ids) if ids.any?
      end

      def upload_to_gridfs(message_record, att)
        att = RubyLLM::Attachment.new(att) unless att.is_a?(RubyLLM::Attachment)
        io  = StringIO.new(att.content.to_s.b)
        file_id = message_record.class.gridfs_bucket.upload_from_stream(
          att.filename,
          io,
          metadata: { content_type: att.mime_type }
        )
        { "id" => file_id, "filename" => att.filename, "content_type" => att.mime_type }
      rescue StandardError => e
        RubyLLM.logger.warn "RubyLLM: GridFS upload failed for #{att.filename}: #{e.message}"
        nil
      end

      def content_raw_field?(record)
        record.class.fields.key?("content_raw")
      end

      def field_declared?(record, name)
        record.class.fields.key?(name.to_s)
      end
    end
  end
end
