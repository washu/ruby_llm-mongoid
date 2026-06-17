# frozen_string_literal: true

RSpec.describe "acts_as_model — class methods" do
  let(:model_info) do
    instance_double(
      RubyLLM::Model::Info,
      id: "gpt-4o-mini",
      name: "GPT-4o mini",
      provider: "openai",
      family: "gpt-4o",
      created_at: nil,
      context_window: 128_000,
      max_output_tokens: 16_384,
      knowledge_cutoff: nil,
      modalities: instance_double("Modalities", to_h: { text: { input: true } }),
      capabilities: ["text"],
      pricing: instance_double("Pricing", to_h: { input: 0.15 }),
      metadata: {}
    )
  end

  describe ".from_llm" do
    it "builds a new (unsaved) LlmModel from a Model::Info" do
      record = LlmModel.from_llm(model_info)
      expect(record).not_to be_persisted
      expect(record.model_id).to eq("gpt-4o-mini")
      expect(record.provider).to eq("openai")
      expect(record.context_window).to eq(128_000)
    end
  end

  describe ".save_to_database" do
    it "upserts all models from RubyLLM.models.all" do
      allow(RubyLLM.models).to receive(:all).and_return([model_info])

      expect { LlmModel.save_to_database }.to change(LlmModel, :count).by(1)

      record = LlmModel.find_by(model_id: "gpt-4o-mini", provider: "openai")
      expect(record).not_to be_nil
      expect(record.name).to eq("GPT-4o mini")
    end

    it "updates existing records on repeat calls" do
      allow(RubyLLM.models).to receive(:all).and_return([model_info])

      LlmModel.save_to_database
      expect { LlmModel.save_to_database }.not_to change(LlmModel, :count)
    end
  end

  describe ".refresh!" do
    it "calls RubyLLM.models.refresh! then persists" do
      allow(RubyLLM.models).to receive(:refresh!).and_return(true)
      allow(RubyLLM.models).to receive(:all).and_return([model_info])

      expect(RubyLLM.models).to receive(:refresh!)
      expect { LlmModel.refresh! }.to change { LlmModel.count }.by(1)
    end
  end

  describe "#to_llm" do
    it "round-trips all scalar fields" do
      m = LlmModel.create!(
        model_id: "gpt-4o-mini",
        provider: "openai",
        name: "GPT-4o mini",
        family: "gpt-4o",
        context_window: 128_000,
        max_output_tokens: 16_384,
        capabilities: ["text"],
        modalities: { "text" => { "input" => true } },
        pricing: { "input" => 0.15 },
        metadata: { "custom" => true }
      )

      info = m.to_llm
      expect(info.id).to eq("gpt-4o-mini")
      expect(info.provider).to eq("openai")
      expect(info.family).to eq("gpt-4o")
      expect(info.context_window).to eq(128_000)
      expect(info.modalities).to be_a(RubyLLM::Model::Modalities)
      expect(info.pricing).to be_a(RubyLLM::Model::Pricing)
      expect(info.metadata).to include("custom" => true)
    end
  end
end
