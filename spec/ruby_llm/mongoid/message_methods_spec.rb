# frozen_string_literal: true

RSpec.describe "acts_as_message — detailed branches" do
  let(:model_record) do
    LlmModel.find_or_create_by!(model_id: "gpt-4o-mini", provider: "openai") do |m|
      m.name = "GPT-4o mini"
      m.capabilities = []
      m.modalities = {}
      m.pricing = {}
      m.metadata = {}
    end
  end
  let(:chat) { Chat.create!(llm_model: model_record) }

  # ─── extract_content ────────────────────────────────────────────────────────

  describe "#to_llm with content_raw field" do
    it "returns Content::Raw when content_raw is present" do
      msg = chat.messages_association.create!(role: "assistant", content: nil,
                                              content_raw: { "type" => "raw", "data" => [1, 2] })
      llm_msg = msg.to_llm
      expect(llm_msg.content).to be_a(RubyLLM::Content::Raw)
    end

    it "returns plain content string when content_raw is absent" do
      msg = chat.messages_association.create!(role: "user", content: "hello")
      expect(msg.to_llm.content).to eq("hello")
    end
  end

  # ─── to_partial_path ────────────────────────────────────────────────────────

  describe "#to_partial_path" do
    it "returns the tool role path" do
      msg = chat.messages_association.create!(role: "tool", content: "result")
      expect(msg.to_partial_path).to end_with("/tool")
    end

    it "returns assistant path when role is nil-ish" do
      msg = chat.messages_association.create!(role: "assistant", content: "hi")
      expect(msg.to_partial_path).to end_with("/assistant")
    end
  end

  # ─── thinking ───────────────────────────────────────────────────────────────

  describe "#thinking" do
    it "returns nil when no thinking fields are present" do
      msg = chat.messages_association.create!(role: "assistant", content: "hi")
      expect(msg.thinking).to be_nil
    end

    it "returns a Thinking when thinking_text is present" do
      msg = chat.messages_association.create!(
        role: "assistant", content: "hi",
        thinking_text: "I reasoned about this.", thinking_signature: "sig123"
      )
      thinking = msg.thinking
      expect(thinking).not_to be_nil
      expect(thinking.text).to eq("I reasoned about this.")
    end
  end

  # ─── tokens ─────────────────────────────────────────────────────────────────

  describe "#tokens" do
    it "includes cached_tokens when the field is present" do
      msg = chat.messages_association.create!(
        role: "assistant", content: "hi",
        input_tokens: 5, output_tokens: 2, cached_tokens: 3
      )
      expect(msg.tokens.cached).to eq(3)
    end

    it "returns nil tokens when input/output tokens are absent" do
      msg = chat.messages_association.create!(role: "user", content: "yo")
      expect(msg.tokens).to be_nil
    end
  end

  # ─── tool_call? / tool_result? delegation ───────────────────────────────────

  describe "#tool_call? and #tool_result?" do
    it "returns false for a plain assistant message" do
      msg = chat.messages_association.create!(role: "assistant", content: "hi")
      expect(msg.tool_call?).to be false
      expect(msg.tool_result?).to be false
    end
  end

  # ─── extract_tool_calls ─────────────────────────────────────────────────────

  describe "extract_tool_calls via to_llm" do
    it "includes persisted ToolCall records as RubyLLM::ToolCall objects" do
      msg = chat.messages_association.create!(role: "assistant", content: nil)
      msg.tool_calls_association.create!(
        tool_call_id: "call_xyz", name: "lookup", arguments: { "q" => "ruby" }
      )

      tc_map = msg.to_llm.tool_calls
      expect(tc_map).to have_key("call_xyz")
      expect(tc_map["call_xyz"].name).to eq("lookup")
    end
  end

  # ─── cost ───────────────────────────────────────────────────────────────────

  describe "#cost" do
    it "returns a Cost even when model_association is nil" do
      msg = chat.messages_association.create!(
        role: "assistant", content: "hi", input_tokens: 3, output_tokens: 1
      )
      expect(msg.cost).to be_a(RubyLLM::Cost)
    end
  end

  # ─── tool_error_message ─────────────────────────────────────────────────────

  describe "#tool_error_message on Message" do
    it "returns error string from JSON content" do
      msg = chat.messages_association.create!(
        role: "tool", content: { "error" => "timeout" }.to_json
      )
      expect(msg.tool_error_message).to eq("timeout")
    end

    it "returns nil when content has no error key" do
      msg = chat.messages_association.create!(role: "tool", content: "ok")
      expect(msg.tool_error_message).to be_nil
    end
  end
end
