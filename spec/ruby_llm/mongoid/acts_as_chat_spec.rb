# frozen_string_literal: true

RSpec.describe "acts_as_chat" do
  let(:model_record) do
    LlmModel.find_or_create_by!(model_id: "gpt-4o-mini", provider: "openai") do |m|
      m.name = "GPT-4o mini"
      m.capabilities = []
      m.modalities = {}
      m.pricing = {}
      m.metadata = {}
    end
  end

  describe "Chat.create! with model object" do
    it "creates a chat and links the model record" do
      chat = Chat.create!(llm_model: model_record)
      expect(chat).to be_persisted
      expect(chat.model_id).to eq("gpt-4o-mini")
      expect(chat.provider).to eq("openai")
    end
  end

  describe "#with_instructions" do
    it "persists a system message" do
      chat = Chat.create!(llm_model: model_record)
      chat.with_instructions("You are a helpful assistant.")

      system_msgs = chat.messages_association.where(role: "system").to_a
      expect(system_msgs.size).to eq(1)
      expect(system_msgs.first.content).to eq("You are a helpful assistant.")
    end

    it "replaces the existing system message by default" do
      chat = Chat.create!(llm_model: model_record)
      chat.with_instructions("First instruction.")
      chat.with_instructions("Replaced instruction.")

      system_msgs = chat.messages_association.where(role: "system").to_a
      expect(system_msgs.size).to eq(1)
      expect(system_msgs.first.content).to eq("Replaced instruction.")
    end

    it "appends when append: true" do
      chat = Chat.create!(llm_model: model_record)
      chat.with_instructions("First.")
      chat.with_instructions("Second.", append: true)

      expect(chat.messages_association.where(role: "system").count).to eq(2)
    end
  end

  describe "#add_message" do
    it "persists a user message with the correct role and content" do
      chat = Chat.create!(llm_model: model_record)
      msg = chat.add_message(RubyLLM::Message.new(role: :user, content: "Hello"))

      expect(msg).to be_persisted
      expect(msg.role).to eq("user")
      expect(msg.content).to eq("Hello")
    end
  end

  describe "#model_id and #provider delegation" do
    it "delegates model_id and provider through the model association" do
      chat = Chat.create!(llm_model: model_record)
      expect(chat.model_id).to eq("gpt-4o-mini")
      expect(chat.provider).to eq("openai")
    end
  end

  describe "Chat.create! with model string" do
    it "resolves the model string to a LlmModel record on save" do
      chat = Chat.new
      chat.model = "gpt-4o-mini"
      chat.save!

      expect(chat.model_association).to be_a(LlmModel)
      expect(chat.model_id).to eq("gpt-4o-mini")
    end
  end

  describe "#cost" do
    it "returns a Cost aggregate across all messages" do
      chat = Chat.create!(llm_model: model_record)
      chat.messages_association.create!(
        role: "assistant", content: "hi", input_tokens: 5, output_tokens: 3,
        llm_model: model_record
      )

      cost = chat.cost
      expect(cost).to be_a(RubyLLM::Cost)
    end
  end

  describe "messages ordered by created_at" do
    it "returns messages in insertion order" do
      chat = Chat.create!(llm_model: model_record)
      chat.add_message(RubyLLM::Message.new(role: :user, content: "First"))
      chat.add_message(RubyLLM::Message.new(role: :user, content: "Second"))

      contents = chat.messages_association.order_by(created_at: :asc).map(&:content)
      expect(contents).to eq(%w[First Second])
    end
  end
end
