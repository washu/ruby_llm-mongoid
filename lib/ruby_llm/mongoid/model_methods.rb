# frozen_string_literal: true

require "active_support/concern"
require "active_support/core_ext/module/delegation"

module RubyLLM
  module Mongoid
    # Mixes into a Mongoid document that represents a persisted LLM model record.
    # Mirrors RubyLLM::ActiveRecord::ModelMethods.
    module ModelMethods
      extend ActiveSupport::Concern

      class_methods do # rubocop:disable Metrics/BlockLength
        def read
          all.map(&:to_llm)
        rescue StandardError => e
          RubyLLM.logger.debug { "Failed to load models from MongoDB: #{e.message}, falling back to JSON" }
          []
        end

        def write(registry)
          save_to_database(registry)
        end

        def description
          "mongodb:#{name}"
        end

        def refresh
          if RubyLLM.models.respond_to?(:refresh)
            RubyLLM.models.refresh
          else
            RubyLLM.models.refresh!
          end

          save_to_database
        end

        alias refresh! refresh

        def save_to_database(registry = RubyLLM.models)
          registry.all.each do |model_info|
            model = find_or_initialize_by(
              model_id: model_info.id,
              provider: model_info.provider
            )
            model.assign_attributes(from_llm_attributes(model_info))
            model.save!
          end
        end

        def from_llm(model_info)
          new(from_llm_attributes(model_info))
        end

        private

        def from_llm_attributes(model_info)
          {
            model_id: model_info.id,
            name: model_info.name,
            provider: model_info.provider,
            family: model_info.family,
            model_created_at: model_info.created_at,
            context_window: model_info.context_window,
            max_output_tokens: model_info.max_output_tokens,
            knowledge_cutoff: model_info.knowledge_cutoff,
            modalities: model_info.modalities.to_h,
            capabilities: model_info.capabilities,
            pricing: model_info.pricing.to_h,
            metadata: model_info.metadata
          }
        end
      end

      def to_llm
        model_class.new(
          id: model_id,
          name: name,
          provider: provider,
          family: family,
          created_at: model_created_at,
          context_window: context_window,
          max_output_tokens: max_output_tokens,
          knowledge_cutoff: knowledge_cutoff,
          modalities: modalities&.deep_symbolize_keys || {},
          capabilities: capabilities,
          pricing: pricing&.deep_symbolize_keys || {},
          metadata: metadata&.deep_symbolize_keys || {}
        )
      end

      delegate :supports?, :type, :provider_class, :label, :cost_for, to: :to_llm

      def supports_vision?
        capability_supported?(:vision, legacy_method: :supports_vision?)
      end

      def supports_functions?
        capability_supported?(:function_calling, legacy_method: :supports_functions?)
      end

      def function_calling?
        capability_supported?(:function_calling, legacy_method: :function_calling?)
      end

      def structured_output?
        capability_supported?(:structured_output, legacy_method: :structured_output?)
      end

      def batch?
        capability_supported?(:batch, legacy_method: :batch?)
      end

      def reasoning?
        capability_supported?(:reasoning, legacy_method: :reasoning?)
      end

      def citations?
        capability_supported?(:citations, legacy_method: :citations?)
      end

      def streaming?
        capability_supported?(:streaming, legacy_method: :streaming?)
      end

      def input_price_per_million
        model_price(:input, legacy_method: :input_price_per_million)
      end

      def output_price_per_million
        model_price(:output, legacy_method: :output_price_per_million)
      end

      def cache_read_input_price_per_million
        model_price(:cache_read, legacy_method: :cache_read_input_price_per_million)
      end

      def cache_write_input_price_per_million
        model_price(:cache_write, legacy_method: :cache_write_input_price_per_million)
      end

      def cached_input_price_per_million
        model_price(:cache_read, legacy_method: :cached_input_price_per_million)
      end

      def cache_creation_input_price_per_million
        model_price(:cache_write, legacy_method: :cache_creation_input_price_per_million)
      end

      private

      def model_class
        return RubyLLM::Model if defined?(RubyLLM::Model) && RubyLLM::Model.is_a?(Class)

        RubyLLM::Model::Info
      end

      def capability_supported?(capability, legacy_method:)
        llm_model = to_llm
        return llm_model.public_send(legacy_method) if llm_model.respond_to?(legacy_method)
        return llm_model.supports?(capability) if llm_model.respond_to?(:supports?)

        false
      end

      def model_price(kind, legacy_method:)
        llm_model = to_llm
        return llm_model.public_send(legacy_method) if llm_model.respond_to?(legacy_method)
        return llm_model.price(kind) if llm_model.respond_to?(:price)

        nil
      end
    end
  end
end
