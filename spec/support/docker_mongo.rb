# frozen_string_literal: true

require "socket"
require "timeout"

# Ensures a MongoDB instance is available for the test suite.
# If nothing is listening on the configured host/port, spins up a
# mongo:8.0 Docker container and tears it down at exit.
module DockerMongo
  CONTAINER_NAME = "ruby-llm-mongoid-mongo"
  HOST = ENV.fetch("MONGODB_HOST", "localhost")
  PORT = ENV.fetch("MONGODB_PORT", "27017").to_i

  class << self
    def ensure_running!
      if reachable?
        warn "[DockerMongo] MongoDB already running on #{HOST}:#{PORT}, skipping container start."
        return
      end

      start_container!
      wait_until_ready!
      at_exit { stop_container! }
    end

    private

    def reachable?
      TCPSocket.new(HOST, PORT).close
      true
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
      false
    end

    def start_container!
      warn "[DockerMongo] Starting mongo:8.0 container '#{CONTAINER_NAME}' on port #{PORT}..."
      success = system(
        "docker", "run", "--detach", "--rm",
        "--name", CONTAINER_NAME,
        "--publish", "#{PORT}:27017",
        "mongo:8.0", "--quiet"
      )
      raise "Failed to start MongoDB Docker container (is Docker running?)" unless success
    end

    def wait_until_ready!
      warn "[DockerMongo] Waiting for MongoDB to accept connections..."
      Timeout.timeout(60) do
        sleep 0.5 until reachable?
      end
      sleep 1 # let mongod finish internal init after port opens
    rescue Timeout::Error
      raise "MongoDB container did not become ready within 60 seconds"
    end

    def stop_container!
      warn "[DockerMongo] Stopping container '#{CONTAINER_NAME}'..."
      system("docker", "stop", CONTAINER_NAME, out: File::NULL, err: File::NULL)
    end
  end
end

DockerMongo.ensure_running!
