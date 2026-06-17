# frozen_string_literal: true

require "base64"
require "tempfile"

RSpec.describe RubyLLM::Mongoid::GridFsAttachment do
  let(:model_record) do
    LlmModel.find_or_create_by!(model_id: "gpt-4o-mini", provider: "openai") do |m|
      m.name = "GPT-4o mini"
      m.capabilities = []
      m.modalities = {}
      m.pricing = {}
      m.metadata = {}
    end
  end

  let(:chat) { GridFsChat.create!(llm_model: model_record) }

  # Tiny valid 1×1 white PNG (68 bytes)
  let(:png_bytes) do
    Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg=="
    )
  end

  let(:png_file) do
    Tempfile.new(["test_image", ".png"]).tap do |f|
      f.binmode
      f.write(png_bytes)
      f.rewind
    end
  end

  describe "GridFsMessage model setup" do
    it "declares gridfs_file_ids field" do
      expect(GridFsMessage.fields).to have_key("gridfs_file_ids")
    end

    it "exposes a gridfs_bucket class method" do
      expect(GridFsMessage.gridfs_bucket).to be_a(Mongo::Grid::FSBucket)
    end

    it "uses 'attachments' as the default bucket name" do
      expect(GridFsMessage.gridfs_bucket_name).to eq("attachments")
    end

    it "allows customising the bucket name" do
      klass = Class.new do
        include Mongoid::Document
        include RubyLLM::Mongoid::GridFsAttachment

        use_gridfs_bucket :custom_files
      end
      expect(klass.gridfs_bucket_name).to eq("custom_files")
    end
  end

  describe "upload on ask" do
    before do
      stub_openai_chat(content: "I see an image.", input_tokens: 15, output_tokens: 5)
    end

    it "stores gridfs_file_ids on the user message after ask with: attachment" do
      chat.ask("What is this?", with: [png_file])

      user_msg = chat.grid_fs_messages.where(role: "user").first
      expect(user_msg.gridfs_file_ids).not_to be_empty
      expect(user_msg.gridfs_file_ids.first).to include("filename", "content_type", "id")
    end

    it "stores the correct filename and content_type" do
      chat.ask("Describe this image.", with: [png_file])

      meta = chat.grid_fs_messages.where(role: "user").first.gridfs_file_ids.first
      expect(meta["filename"]).to end_with(".png")
      expect(meta["content_type"]).to eq("image/png")
    end

    it "does not set gridfs_file_ids on the assistant message" do
      chat.ask("Describe this image.", with: [png_file])

      assistant_msg = chat.grid_fs_messages.where(role: "assistant").first
      expect(assistant_msg.gridfs_file_ids).to be_empty
    end
  end

  describe "#extract_content (round-trip via to_llm)" do
    before do
      stub_openai_chat(content: "I see an image.", input_tokens: 15, output_tokens: 5)
    end

    it "returns a RubyLLM::Content object when gridfs files are present" do
      chat.ask("Describe this.", with: [png_file])

      user_msg = chat.grid_fs_messages.where(role: "user").first
      result = user_msg.to_llm.content
      expect(result).to be_a(RubyLLM::Content)
    end

    it "includes the original attachment bytes" do
      chat.ask("Describe this.", with: [png_file])

      user_msg = chat.grid_fs_messages.where(role: "user").first
      content  = user_msg.to_llm.content
      attachment = content.attachments.first
      expect(attachment.content).to eq(png_bytes)
    end
  end

  describe "GridFS cleanup on destroy" do
    before do
      stub_openai_chat(content: "I see an image.", input_tokens: 15, output_tokens: 5)
    end

    def bucket
      GridFsMessage.gridfs_bucket
    end

    it "deletes GridFS files when the message is destroyed" do
      chat.ask("Describe this.", with: [png_file])
      user_msg = chat.grid_fs_messages.where(role: "user").first
      file_id  = user_msg.gridfs_file_ids.first["id"]

      user_msg.destroy

      expect { bucket.open_download_stream(file_id, &:read) }.to raise_error(Mongo::Error::FileNotFound)
    end

    it "deletes all GridFS files when the chat is destroyed" do
      chat.ask("Describe this.", with: [png_file])
      user_msg = chat.grid_fs_messages.where(role: "user").first
      file_id  = user_msg.gridfs_file_ids.first["id"]

      chat.destroy

      expect { bucket.open_download_stream(file_id, &:read) }.to raise_error(Mongo::Error::FileNotFound)
    end

    it "leaves GridFS intact when a message without attachments is destroyed" do
      chat.ask("Describe this.", with: [png_file])
      assistant_msg = chat.grid_fs_messages.where(role: "assistant").first

      expect { assistant_msg.destroy }.not_to raise_error
    end
  end

  describe "message without gridfs files" do
    it "returns plain text when gridfs_file_ids is empty" do
      msg = chat.grid_fs_messages.create!(role: "user", content: "hello")
      expect(msg.to_llm.content).to eq("hello")
    end
  end
end
