# frozen_string_literal: true

module RubyLLM
  module Mongoid
    # Wraps a block in a MongoDB multi-document transaction when a replica set is
    # available. Falls back to a plain yield on standalone mongod so tests and
    # single-node dev setups still work without errors.
    module Transaction
      def with_transaction(&)
        _run_transaction(&)
      rescue ::Mongoid::Errors::TransactionsNotSupported, ::Mongo::Error::TransactionsNotSupported
        yield
      rescue ::Mongo::Error::OperationFailure => e
        raise unless standalone_mongod_error?(e)

        yield
      rescue NotImplementedError, NoMethodError # rubocop:disable Lint/DuplicateBranch
        yield
      end

      private

      def _run_transaction(&block)
        if ::Mongoid.respond_to?(:with_session)
          ::Mongoid.with_session do |session|
            session.with_transaction(&block)
          end
        else
          yield
        end
      end

      def standalone_mongod_error?(error)
        # Error code 20 is "IllegalOperation" which is returned when transactions
        # are used on a standalone mongod.
        return true if error.respond_to?(:code) && error.code == 20

        msg = error.message
        msg.include?("Transaction numbers are only allowed") ||
          msg.include?("no such command: 'startTransaction'")
      end
    end
  end
end
