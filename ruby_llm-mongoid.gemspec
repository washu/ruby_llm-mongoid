# frozen_string_literal: true

require_relative "lib/ruby_llm/mongoid/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_llm-mongoid"
  spec.version = RubyLLM::Mongoid::VERSION
  spec.authors = ["washu"]
  spec.email = ["sal.scotto@gmail.com"]

  spec.summary = "Mongoid persistence for ruby_llm (acts_as_chat, acts_as_message, acts_as_tool_call, acts_as_model)"
  spec.description = "Drop-in Mongoid replacement for ruby_llm's ActiveRecord integration. " \
                     "Provides acts_as_chat, acts_as_message, acts_as_tool_call, and acts_as_model " \
                     "macros backed by MongoDB via Mongoid."
  spec.homepage = "https://github.com/SalScotto/ruby_llm-mongoid"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "mongoid", ">= 8.0"
  spec.add_dependency "ruby_llm", ">= 1.16"
end
