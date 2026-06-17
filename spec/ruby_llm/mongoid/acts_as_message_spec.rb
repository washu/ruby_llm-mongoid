# frozen_string_literal: true

RSpec.describe "acts_as_message" do
  let(:model_record) do
    LlmModel.find_or_create_by!(model_id: "gpt-4o-mini", provider: "openai") do |m|
      m.name = "GPT-4o mini"
      m.capabilities = []
      m.modalities = {}
      m.pricing = {}
      m.metadata = {}
    end
  end

  let(:chat) { Chat.create!(model: model_record) }

  describe "#to_llm" do
    it "returns a RubyLLM::Message" do
      msg = chat.messages_association.create!(role: "user", content: "Hello")
      expect(msg.to_llm).to be_a(RubyLLM::Message)
      expect(msg.to_llm.role).to eq(:user)
      expect(msg.to_llm.content).to eq("Hello")
    end
  end

  describe "#tokens" do
    it "returns a Tokens struct" do
      msg = chat.messages_association.create!(
        role: "assistant",
        content: "Hi",
        input_tokens: 10,
        output_tokens: 5
      )
      tokens = msg.tokens
      expect(tokens.input).to eq(10)
      expect(tokens.output).to eq(5)
    end
  end

  describe "#cost" do
    it "returns a Cost" do
      msg = chat.messages_association.create!(
        role: "assistant",
        content: "Hi",
        input_tokens: 10,
        output_tokens: 5
      )
      begin
        msg.update!(model_association_name => model_record)
      rescue StandardError
        nil
      end
      expect(msg.cost).to be_a(RubyLLM::Cost)
    end
  end

  describe "#to_partial_path" do
    it "returns path with role" do
      msg = chat.messages_association.create!(role: "user", content: "yo")
      expect(msg.to_partial_path).to eq("messages/user")
    end
  end

  describe "extract_tool_calls" do
    it "returns empty hash when no tool calls" do
      msg = chat.messages_association.create!(role: "assistant", content: "hi")
      expect(msg.to_llm.tool_calls).to eq({})
    end
  end
end
