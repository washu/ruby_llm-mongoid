# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  minimum_coverage line: 90, branch: 50
  add_filter "/spec/"
  add_filter "/lib/generators/"
  add_group "Core", "lib/ruby_llm/mongoid"
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [SimpleCov::Formatter::HTMLFormatter]
  )
end

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "ruby_llm/mongoid"
require "database_cleaner/mongoid"
require "vcr"
require "webmock/rspec"

# ─── MongoDB availability ──────────────────────────────────────────────────────
# Starts a mongo:8.0 Docker container if no MongoDB is already reachable.
# In CI, ci.yml starts one first; locally, Docker handles it automatically.

require_relative "support/docker_mongo"

# ─── Mongoid configuration ────────────────────────────────────────────────────

Mongoid.configure do |config|
  config.load_configuration(
    clients: {
      default: {
        database: "ruby_llm_mongoid_test",
        hosts: ["#{ENV.fetch("MONGODB_HOST", "localhost")}:#{ENV.fetch("MONGODB_PORT", "27017")}"],
        options: { server_selection_timeout: 5 }
      }
    }
  )
end

# ─── Support files ────────────────────────────────────────────────────────────

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

# ─── VCR ──────────────────────────────────────────────────────────────────────

VCR.configure do |config|
  config.cassette_library_dir = File.join(__dir__, "cassettes")
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<OPENAI_API_KEY>")    { ENV.fetch("OPENAI_API_KEY", "test-key") }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV.fetch("ANTHROPIC_API_KEY", "test-key") }
  config.default_cassette_options = {
    record: :none,
    allow_playback_repeats: true
  }
end

# ─── RubyLLM ──────────────────────────────────────────────────────────────────

RubyLLM.configure do |config|
  config.openai_api_key    = ENV.fetch("OPENAI_API_KEY", "test-openai-key")
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "test-anthropic-key")
end

# ─── RSpec ────────────────────────────────────────────────────────────────────

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:suite) do
    DatabaseCleaner[:mongoid].strategy = :deletion
    DatabaseCleaner[:mongoid].clean_with(:deletion)
  end

  config.around do |example|
    DatabaseCleaner[:mongoid].cleaning { example.run }
  end
end
