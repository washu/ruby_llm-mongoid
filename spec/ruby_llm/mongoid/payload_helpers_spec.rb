# frozen_string_literal: true

# PayloadHelpers is included in MessageMethods and ToolCallMethods.
# Test edge cases via a thin wrapper.
RSpec.describe RubyLLM::Mongoid::PayloadHelpers do
  subject(:helper) do
    Object.new.tap { |o| o.extend(described_class) }
  end

  describe "#tool_error_message (via payload_error_message)" do
    it "returns nil for a plain String value (no JSON)" do
      expect(helper.send(:payload_error_message, "plain text")).to be_nil
    end

    it "returns nil when value is blank" do
      expect(helper.send(:payload_error_message, nil)).to be_nil
      expect(helper.send(:payload_error_message, "")).to be_nil
    end

    it "returns nil for an Array payload with no error key" do
      expect(helper.send(:payload_error_message, [1, 2, 3])).to be_nil
    end

    it "returns nil for a Hash with no error key" do
      expect(helper.send(:payload_error_message, { "foo" => "bar" })).to be_nil
    end

    it "returns the error from a Hash payload" do
      expect(helper.send(:payload_error_message, { "error" => "oops" })).to eq("oops")
    end

    it "returns the error from a JSON string" do
      json = { "error" => "something went wrong" }.to_json
      expect(helper.send(:payload_error_message, json)).to eq("something went wrong")
    end

    it "returns nil for invalid JSON" do
      expect(helper.send(:payload_error_message, "{not json}")).to be_nil
    end
  end
end
