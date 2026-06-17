# frozen_string_literal: true

# Tests that exercise the field_declared? FALSE branches — paths taken when a
# user's message model omits the optional fields (thinking_text, cached_tokens,
# content_raw, etc.).  MinimalMessage only has :role and :content.
RSpec.describe "minimal message model (optional fields absent)" do
  let(:model_record) do
    LlmModel.find_or_create_by!(model_id: "gpt-4o-mini", provider: "openai") do |m|
      m.name = "GPT-4o mini"
      m.capabilities = []
      m.modalities = {}
      m.pricing = {}
      m.metadata = {}
    end
  end

  let(:chat) { MinimalChat.create!(llm_model: model_record) }

  describe "#to_llm on MinimalMessage" do
    it "returns a RubyLLM::Message with plain content" do
      msg = chat.minimal_messages.create!(role: "user", content: "hello")
      expect(msg.to_llm.content).to eq("hello")
    end

    it "has nil thinking when thinking fields are absent" do
      msg = chat.minimal_messages.create!(role: "assistant", content: "hi")
      expect(msg.thinking).to be_nil
    end

    it "has nil tokens when token fields are absent" do
      msg = chat.minimal_messages.create!(role: "assistant", content: "hi")
      expect(msg.tokens).to be_nil
    end
  end

  describe "#add_message on MinimalChat (no content_raw field)" do
    before { stub_openai_chat(content: "Minimal reply.", input_tokens: 3, output_tokens: 2) }

    it "persists a complete ask round-trip without optional fields" do
      expect { chat.ask("Hello from minimal!") }.to change { MinimalMessage.count }.by(2)
    end

    it "stores the assistant response content correctly" do
      chat.ask("Hello!")
      assistant = chat.minimal_messages.where(role: "assistant").first
      expect(assistant.content).to eq("Minimal reply.")
    end
  end
end
