# frozen_string_literal: true

require "rails/generators"

module RubyLLM
  module Generators
    module Mongoid
      # Generator that scaffolds Mongoid model files for ruby_llm-mongoid.
      # Unlike the ActiveRecord generator there are no migrations — Mongoid models
      # declare their fields inline.
      #
      # Usage:
      #   bin/rails g ruby_llm:mongoid:install [chat:ChatName] [message:MessageName] ...
      class InstallGenerator < Rails::Generators::Base
        namespace "ruby_llm:mongoid:install"

        source_root File.expand_path("templates", __dir__)

        argument :model_mappings, type: :array, default: [],
                                  banner: "chat:ChatName message:MessageName ..."

        desc "Creates Mongoid model files for the ruby_llm-mongoid integration."

        def create_model_files
          template "chat_model.rb.tt",      "app/models/#{chat_model_name.underscore}.rb"
          template "message_model.rb.tt",   "app/models/#{message_model_name.underscore}.rb"
          template "tool_call_model.rb.tt", "app/models/#{tool_call_model_name.underscore}.rb"
          template "model_model.rb.tt",     "app/models/#{model_model_name.underscore}.rb"
        end

        def create_initializer
          template "initializer.rb.tt", "config/initializers/ruby_llm.rb"
        end

        def create_convention_directories
          %w[agents tools schemas prompts].each do |name|
            empty_directory "app/#{name}"
          end
        end

        def show_install_info
          say "\n  ruby_llm-mongoid installed!", :green
          say "\n  Next steps:", :yellow
          say "     1. Ensure mongoid.yml is configured (bin/rails g mongoid:config)"
          say "     2. Run: bin/rails ruby_llm:mongoid:create_indexes"
          say "     3. Set your API keys in config/initializers/ruby_llm.rb"
          say "     4. Start chatting: #{chat_model_name}.create!(model: 'gpt-4.1-nano').ask('Hello!')"
          say "\n  Documentation: https://github.com/SalScotto/ruby_llm-mongoid\n", :cyan
        end

        private

        def mappings
          @mappings ||= parse_mappings
        end

        def parse_mappings
          result = { "chat" => "Chat", "message" => "Message",
                     "tool_call" => "ToolCall", "model" => "LlmModel" }
          model_mappings.each do |pair|
            key, value = pair.split(":")
            result[key] = value if key && value
          end
          result
        end

        def chat_model_name
          mappings.fetch("chat", "Chat")
        end

        def message_model_name
          mappings.fetch("message", "Message")
        end

        def tool_call_model_name
          mappings.fetch("tool_call", "ToolCall")
        end

        def model_model_name
          mappings.fetch("model", "LlmModel")
        end
      end
    end
  end
end
