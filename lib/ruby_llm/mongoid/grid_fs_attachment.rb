# frozen_string_literal: true

require "active_support/concern"
require "tmpdir"

module RubyLLM
  module Mongoid
    # Optional concern for message models that want GridFS-backed file attachments
    # instead of Active Storage.
    #
    # Usage:
    #   class Message
    #     include Mongoid::Document
    #     include RubyLLM::Mongoid::GridFsAttachment
    #     acts_as_message
    #   end
    #
    # Each uploaded file is stored in a MongoDB GridFS bucket (default: "attachments").
    # Metadata is tracked in the +gridfs_file_ids+ array field on the document.
    #
    # To use a different bucket name:
    #   class Message
    #     include RubyLLM::Mongoid::GridFsAttachment
    #     use_gridfs_bucket :llm_files
    #   end
    module GridFsAttachment
      extend ActiveSupport::Concern

      included do
        # Array of { "id" => BSON::ObjectId, "filename" => String, "content_type" => String }
        field :gridfs_file_ids, type: Array, default: []

        before_destroy :delete_gridfs_files
        after_find :cleanup_gridfs_tempfiles
        after_save :cleanup_gridfs_tempfiles
      end

      # Cleanup tempfiles created during download
      def cleanup_gridfs_tempfiles
        return unless defined?(@_gridfs_tempfiles) && @_gridfs_tempfiles

        @_gridfs_tempfiles.each do |f|
          f.close
          f.unlink
        rescue StandardError => e
          RubyLLM.logger.warn "RubyLLM: Failed to cleanup GridFS tempfile #{f.path}: #{e.message}"
        end
        @_gridfs_tempfiles = []
      end

      # Builds a RubyLLM::Content that streams each stored file back from GridFS.
      # Called by message_methods#extract_content when gridfs_file_ids is non-empty.
      def gridfs_content(text)
        sources = gridfs_file_ids.filter_map { |meta| download_gridfs_file(meta) }
        return text if sources.empty?

        if text.present?
          RubyLLM::Content.new(text).tap { |c| sources.each { |f, name| c.add_attachment(f, filename: name) } }
        else
          RubyLLM::Content.new(nil, sources.map(&:first))
        end
      end

      module ClassMethods
        def use_gridfs_bucket(name)
          @gridfs_bucket_name = name.to_s
          @_gridfs_bucket = nil
        end

        def gridfs_bucket_name
          @gridfs_bucket_name ||= "attachments"
        end

        def gridfs_bucket
          @gridfs_bucket ||= ::Mongo::Grid::FSBucket.new(
            ::Mongoid.default_client.database,
            fs_name: gridfs_bucket_name
          )
        end
      end

      private

      def delete_gridfs_files
        gridfs_file_ids.each do |meta|
          self.class.gridfs_bucket.delete(coerce_object_id(meta["id"]))
        rescue ::Mongo::Error => e
          RubyLLM.logger.warn "RubyLLM: GridFS delete failed for #{meta.inspect}: #{e.message}"
        end
      end

      def download_gridfs_file(meta)
        filename = meta["filename"].to_s
        io       = fetch_gridfs_stream(meta["id"])
        tmpfile  = stream_to_tempfile(io, filename)
        (@_gridfs_tempfiles ||= []) << tmpfile
        [tmpfile, filename]
      rescue ::Mongo::Error => e
        RubyLLM.logger.warn "RubyLLM: GridFS download failed for #{meta.inspect}: #{e.message}"
        nil
      end

      def fetch_gridfs_stream(id)
        io = StringIO.new("".b)
        self.class.gridfs_bucket.download_to_stream(coerce_object_id(id), io)
        io.tap(&:rewind)
      end

      def stream_to_tempfile(io, filename)
        ext  = File.extname(filename)
        base = File.basename(filename, ext)
        Tempfile.new([base, ext], Dir.tmpdir, encoding: "BINARY").tap do |f|
          f.write(io.read)
          f.rewind
        end
      end

      def coerce_object_id(id)
        return id if id.is_a?(BSON::ObjectId)

        BSON::ObjectId.from_string(id.to_s)
      end
    end
  end
end
