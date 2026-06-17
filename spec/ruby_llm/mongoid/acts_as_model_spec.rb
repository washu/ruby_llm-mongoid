# frozen_string_literal: true

RSpec.describe "acts_as_model" do
  describe "LlmModel fields" do
    it "creates and persists a model record" do
      m = LlmModel.create!(
        model_id: "gpt-4o-mini",
        provider: "openai",
        name: "GPT-4o mini",
        capabilities: ["text"],
        modalities: { text: { input: true, output: true } },
        pricing: {},
        metadata: {}
      )

      reloaded = LlmModel.find(m.id)
      expect(reloaded.model_id).to eq("gpt-4o-mini")
      expect(reloaded.provider).to eq("openai")
    end
  end

  describe "#to_llm" do
    it "returns a Model::Info" do
      m = LlmModel.create!(
        model_id: "gpt-4o-mini",
        provider: "openai",
        name: "GPT-4o mini",
        capabilities: [],
        modalities: {},
        pricing: {},
        metadata: {}
      )
      info = m.to_llm
      expect(info).to be_a(RubyLLM::Model::Info)
      expect(info.id).to eq("gpt-4o-mini")
      expect(info.provider).to eq("openai")
    end
  end

  describe "validations" do
    it "requires model_id, provider, and name" do
      m = LlmModel.new
      expect(m).not_to be_valid
      expect(m.errors[:model_id]).not_to be_empty
      expect(m.errors[:provider]).not_to be_empty
      expect(m.errors[:name]).not_to be_empty
    end

    it "enforces uniqueness of model_id scoped to provider" do
      LlmModel.create!(model_id: "gpt-4o-mini", provider: "openai", name: "GPT",
                       capabilities: [], modalities: {}, pricing: {}, metadata: {})
      dup = LlmModel.new(model_id: "gpt-4o-mini", provider: "openai", name: "GPT2",
                         capabilities: [], modalities: {}, pricing: {}, metadata: {})
      expect(dup).not_to be_valid
    end
  end
end
