# frozen_string_literal: true

RSpec.describe RubyLLM::Mongoid::Transaction do
  subject(:host) do
    Class.new do
      include RubyLLM::Mongoid::Transaction

      def call_with_transaction(&block)
        with_transaction(&block)
      end
    end.new
  end

  describe "#with_transaction" do
    it "yields the block on success" do
      result = host.call_with_transaction { 42 }
      expect(result).to eq(42)
    end

    it "falls back to yielding when TransactionsNotSupported is raised" do
      allow(host).to receive(:_run_transaction).and_raise(
        Mongoid::Errors::TransactionsNotSupported
      )
      result = host.call_with_transaction { "fallback" }
      expect(result).to eq("fallback")
    end

    it "falls back to yielding on NotImplementedError" do
      allow(host).to receive(:_run_transaction).and_raise(NotImplementedError)
      result = host.call_with_transaction { "ni_fallback" }
      expect(result).to eq("ni_fallback")
    end

    it "falls back to yielding on NoMethodError" do
      allow(host).to receive(:_run_transaction).and_raise(NoMethodError)
      result = host.call_with_transaction { "nm_fallback" }
      expect(result).to eq("nm_fallback")
    end

    it "falls back on OperationFailure with standalone topology message" do
      err = Mongo::Error::OperationFailure.new("Transaction numbers are only allowed")
      allow(host).to receive(:_run_transaction).and_raise(err)
      result = host.call_with_transaction { "op_fallback" }
      expect(result).to eq("op_fallback")
    end

    it "re-raises OperationFailure for unrelated errors" do
      err = Mongo::Error::OperationFailure.new("some other mongo error")
      allow(host).to receive(:_run_transaction).and_raise(err)
      expect { host.call_with_transaction { "x" } }.to raise_error(Mongo::Error::OperationFailure)
    end
  end
end
