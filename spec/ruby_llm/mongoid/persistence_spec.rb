# frozen_string_literal: true

# Defined at top level so ruby_llm's `description` DSL doesn't clash with Ruby's Class#name.
class GetWeatherTool < RubyLLM::Tool
  description "Get weather for a city"
  param :city, type: :string, desc: "City name"
  def execute(city:) = "Sunny in #{city}"
end

# Tests the full LLM → persistence round-trip: ask → HTTP stub → callback → DB.
RSpec.describe "LLM persistence round-trip" do
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

  # ─── Basic ask/complete ─────────────────────────────────────────────────────

  describe "#ask — happy path" do
    before { stub_openai_chat(content: "Paris.", input_tokens: 8, output_tokens: 3) }

    it "persists user and assistant messages" do
      expect { chat.ask("Capital of France?") }.to change { Message.count }.by(2)
    end

    it "sets role correctly on both messages" do
      chat.ask("Capital of France?")
      roles = chat.messages_association.order_by(created_at: :asc).map(&:role)
      expect(roles).to eq(%w[user assistant])
    end

    it "stores the assistant response content" do
      chat.ask("Capital of France?")
      assistant = chat.messages_association.where(role: "assistant").first
      expect(assistant.content).to eq("Paris.")
    end

    it "stores token counts on the assistant message" do
      chat.ask("Capital of France?")
      assistant = chat.messages_association.where(role: "assistant").first
      expect(assistant.input_tokens).to be_a(Integer)
      expect(assistant.output_tokens).to eq(3)
    end

    it "links the model record to the assistant message" do
      chat.ask("Capital of France?")
      assistant = chat.messages_association.where(role: "assistant").first
      expect(assistant.model_association).to eq(model_record)
    end
  end

  describe "#say (alias for ask)" do
    before { stub_openai_chat(content: "Hi!") }

    it "works identically to ask" do
      expect { chat.say("Hello") }.to change { Message.count }.by(2)
    end
  end

  describe "#complete called directly" do
    before { stub_openai_chat(content: "Sure.") }

    it "completes without adding a user message first if one exists" do
      chat.messages_association.create!(role: "user", content: "do it")
      expect { chat.complete }.to change { Message.count }.by(1)
    end
  end

  # ─── with_model ─────────────────────────────────────────────────────────────

  describe "#with_model" do
    it "switches the chat to a different model record" do
      LlmModel.find_or_create_by!(model_id: "gpt-4o", provider: "openai") do |m|
        m.name = "GPT-4o"
        m.capabilities = []
        m.modalities = {}
        m.pricing = {}
        m.metadata = {}
      end

      stub_openai_chat(content: "Ok.", model: "gpt-4o")
      chat.with_model("gpt-4o")
      expect(chat.model_id).to eq("gpt-4o")
    end
  end

  # ─── with_temperature / with_params / with_headers / with_schema ────────────

  describe "parameter passthrough" do
    before { stub_openai_chat(content: "ok") }

    it "#with_temperature returns self and asks successfully" do
      result = chat.with_temperature(0.5)
      expect(result).to eq(chat)
      expect { result.ask("hi") }.to change { Message.count }.by(2)
    end

    it "#with_params returns self" do
      expect(chat.with_params(max_tokens: 100)).to eq(chat)
    end

    it "#with_headers returns self" do
      expect(chat.with_headers("X-Custom" => "val")).to eq(chat)
    end
  end

  # ─── Runtime instructions ───────────────────────────────────────────────────

  describe "#with_runtime_instructions" do
    before { stub_openai_chat(content: "Oui.") }

    it "does not persist runtime instructions to DB" do
      chat.with_runtime_instructions("Reply only in French.")
      expect(chat.messages_association.where(role: "system").count).to eq(0)
    end

    it "re-applies runtime instructions on each to_llm call" do
      chat.with_runtime_instructions("Reply only in French.")
      chat.ask("Hello?")
      # subsequent to_llm call still works (no error)
      expect { chat.ask("Again?") }.to change { Message.count }.by(2)
    end
  end

  # ─── Tool call flow ──────────────────────────────────────────────────────────

  describe "tool call persistence" do
    before do
      stub_request(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          { status: 200,
            headers: { "Content-Type" => "application/json" },
            body: {
              "id" => "chatcmpl-tool",
              "object" => "chat.completion",
              "model" => "gpt-4o-mini",
              "choices" => [{
                "index" => 0,
                "message" => {
                  "role" => "assistant",
                  "content" => nil,
                  "tool_calls" => openai_tool_call(id: "call_1", name: "get_weather",
                                                   arguments: { "city" => "NYC" })
                },
                "finish_reason" => "tool_calls"
              }],
              "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
            }.to_json },
          { status: 200,
            headers: { "Content-Type" => "application/json" },
            body: {
              "id" => "chatcmpl-final",
              "object" => "chat.completion",
              "model" => "gpt-4o-mini",
              "choices" => [{
                "index" => 0,
                "message" => { "role" => "assistant", "content" => "It is sunny in NYC." },
                "finish_reason" => "stop"
              }],
              "usage" => { "prompt_tokens" => 20, "completion_tokens" => 8, "total_tokens" => 28 }
            }.to_json }
        )
    end

    it "persists ToolCall documents when the assistant returns tool calls" do
      expect do
        chat.with_tool(GetWeatherTool).ask("What is the weather?")
      end.to change { ToolCall.count }.by_at_least(1)
    end

    it "stores tool_call_id and name on the ToolCall record" do
      chat.with_tool(GetWeatherTool).ask("What is the weather?")
      tc = ToolCall.where(tool_call_id: "call_1").first
      expect(tc).not_to be_nil
      expect(tc.name).to eq("get_weather")
    end
  end

  # ─── Error recovery ──────────────────────────────────────────────────────────

  describe "API error cleanup" do
    it "raises RubyLLM::Error and leaves no dangling empty assistant message" do
      stub_openai_chat_error
      chat.messages_association.create!(role: "user", content: "Hello?")

      expect { chat.complete }.to raise_error(RubyLLM::Error)
      expect(Message.where(role: "assistant", content: "").count).to eq(0)
    end
  end

  # ─── Callbacks ───────────────────────────────────────────────────────────────

  describe "on_new_message / on_end_message callbacks" do
    before { stub_openai_chat(content: "Callback test.") }

    it "fires on_new_message before streaming the response" do
      seen_new = false
      chat.on_new_message { seen_new = true }
      chat.ask("hello")
      expect(seen_new).to be true
    end

    it "fires on_end_message with the completed message" do
      seen_content = nil
      chat.on_end_message { |msg| seen_content = msg.content }
      chat.ask("hello")
      expect(seen_content).to eq("Callback test.")
    end
  end

  # ─── Cost aggregate ──────────────────────────────────────────────────────────

  describe "#cost" do
    before { stub_openai_chat(content: "Hi.", input_tokens: 10, output_tokens: 4) }

    it "aggregates cost across all messages" do
      chat.ask("Hello!")
      expect(chat.cost).to be_a(RubyLLM::Cost)
    end
  end

  # ─── to_llm replay ───────────────────────────────────────────────────────────

  describe "#to_llm replay across multiple turns" do
    before { stub_openai_chat(content: "Sure.") }

    it "replays persisted messages into the LLM chat object" do
      chat.ask("First message")
      stub_openai_chat(content: "Second reply.")
      chat.ask("Second message")

      expect(chat.messages_association.count).to eq(4)
    end
  end

  # ─── content_raw path ────────────────────────────────────────────────────────

  describe "#add_message with raw content" do
    it "stores content_raw when message content is a Hash" do
      raw_msg = RubyLLM::Message.new(
        role: :assistant,
        content: RubyLLM::Content::Raw.new({ "blocks" => ["text"] })
      )
      msg = chat.add_message(raw_msg)

      msg.reload
      expect(msg.content_raw).to eq({ "blocks" => ["text"] })
      expect(msg.content).to be_nil
    end
  end

  # ─── before_tool_call / on_tool_call / on_tool_result passthroughs ──────────

  describe "additional chat passthroughs" do
    before { stub_openai_chat(content: "ok") }

    # rubocop:disable Lint/EmptyBlock
    it "#before_tool_call returns self" do
      expect(chat.before_tool_call {}).to eq(chat)
    end

    it "#after_tool_result returns self" do
      expect(chat.after_tool_result {}).to eq(chat)
    end

    it "#on_tool_call returns self" do
      expect(chat.on_tool_call {}).to eq(chat)
    end

    it "#on_tool_result returns self" do
      expect(chat.on_tool_result {}).to eq(chat)
    end
    # rubocop:enable Lint/EmptyBlock

    it "#with_thinking returns self" do
      expect(chat.with_thinking(budget: 1024)).to eq(chat)
    end

    it "#with_schema returns self" do
      schema = { type: "object", properties: {} }
      expect(chat.with_schema(schema)).to eq(chat)
    end

    it "#create_user_message persists a user message" do
      expect { chat.create_user_message("A direct user message") }
        .to change { Message.where(role: "user").count }.by(1)
    end
  end

  # ─── MongoidSource ────────────────────────────────────────────────────────────

  describe "MongoidSource" do
    let(:source) { RubyLLM::Mongoid::MongoidSource.new }

    before do
      RubyLLM.configure { |c| c.model_registry_class = "LlmModel" }
    end

    it "returns empty array when no model records exist" do
      expect(source.read).to eq([])
    end

    it "returns Model::Info objects for persisted model records" do
      LlmModel.create!(model_id: "gpt-4o-mini", provider: "openai", name: "GPT",
                       capabilities: [], modalities: {}, pricing: {}, metadata: {})
      results = source.read
      expect(results).not_to be_empty
      expect(results.first).to be_a(RubyLLM::Model::Info)
    end

    it "resolves model_registry_class from a String constant name" do
      RubyLLM.configure { |c| c.model_registry_class = "LlmModel" }
      expect { source.read }.not_to raise_error
    end
  end
end
