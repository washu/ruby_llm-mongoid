# frozen_string_literal: true

RSpec.describe "acts_as_tool_call" do
  let(:model_record) do
    LlmModel.find_or_create_by!(model_id: "gpt-4o-mini", provider: "openai") do |m|
      m.name = "GPT-4o mini"
      m.capabilities = []
      m.modalities = {}
      m.pricing = {}
      m.metadata = {}
    end
  end

  let(:chat)    { Chat.create!(model: model_record) }
  let(:message) { chat.messages_association.create!(role: "assistant", content: "") }

  describe "persistence" do
    it "creates a ToolCall associated to a message" do
      tc = message.tool_calls_association.create!(
        tool_call_id: "call_abc123",
        name: "get_weather",
        arguments: { city: "NYC" }
      )
      expect(tc).to be_persisted
      expect(tc.tool_call_id).to eq("call_abc123")
      expect(tc.arguments).to eq({ "city" => "NYC" })
    end
  end

  describe "#tool_error_message" do
    it "returns nil when arguments has no error key" do
      tc = message.tool_calls_association.create!(
        tool_call_id: "call_123",
        name: "search",
        arguments: { q: "hello" }
      )
      expect(tc.tool_error_message).to be_nil
    end

    it "returns the error message when present" do
      tc = message.tool_calls_association.create!(
        tool_call_id: "call_err",
        name: "search",
        arguments: { "error" => "not found" }
      )
      expect(tc.tool_error_message).to eq("not found")
    end
  end

  describe "result association" do
    it "allows linking a result message via parent_tool_call_id" do
      tc = message.tool_calls_association.create!(
        tool_call_id: "call_xyz",
        name: "do_thing",
        arguments: {}
      )
      result_msg = chat.messages_association.create!(
        role: "tool",
        content: "done",
        parent_tool_call: tc
      )
      tc.reload
      expect(tc.result_association).to eq(result_msg)
    end
  end
end
