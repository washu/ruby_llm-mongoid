# frozen_string_literal: true

require "rails/railtie"

module RubyLLM
  module Mongoid
    class Railtie < Rails::Railtie
      initializer "ruby_llm.mongoid.acts_as" do
        ActiveSupport.on_load(:mongoid) do
          ::Mongoid::Document::ClassMethods.include(RubyLLM::Mongoid::ActsAs::ClassMethods)
        end
      end
    end
  end
end
