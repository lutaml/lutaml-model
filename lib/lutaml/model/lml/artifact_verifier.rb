# frozen_string_literal: true

require "digest"
require "json"
require "pathname"

module Lutaml
  module Model
    module Lml
      # Verifies a caller-pinned manifest before any target artifact is loaded.
      class ArtifactVerifier
        class Error < StandardError
          attr_reader :reason, :location

          def initialize(reason, location)
            @reason = reason
            @location = location
            super("#{reason}: #{location}")
          end
        end

        TARGETS = %w[ruby ts rust wasm].freeze
        INVALID_PATH_PARTS = ["", ".", ".."].freeze
        DIGEST = /\Asha256:[0-9a-f]{64}\z/

        def initialize(root:, expected_sha256:, schema_version: 2,
                       target: nil, lml_checksum: nil, generator_version: nil,
                       corpora: nil, dependencies: nil)
          @root = Pathname.new(root).realpath
          @expected_sha256 = expected_sha256
          @expected = {
            "schema_version" => schema_version, "target" => target,
            "lml_checksum" => lml_checksum, "generator_version" => generator_version,
            "corpora" => corpora, "dependencies" => dependencies
          }.compact
        end

        def verify(manifest)
          fail_with(:invalid_document, "/") unless manifest.is_a?(::Hash)
          validate_header(manifest)
          actual = self.class.checksum(manifest)
          unless digest?(@expected_sha256) && actual == @expected_sha256
            fail_with(:checksum_mismatch, "/manifest")
          end
          @expected.each do |key, value|
            next if manifest[key] == value

            fail_with(key == "schema_version" ? :unsupported_version : :checksum_mismatch,
                      "/#{key}")
          end
          verify_files(manifest.fetch("files"))
          deep_freeze(manifest)
        end

        def self.checksum(value)
          "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical(value)))}"
        end

        def self.canonical(value)
          case value
          when ::Hash
            unless value.keys.all?(::String)
              raise Error.new(:invalid_document, "object keys must be strings")
            end

            value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
          when ::Array then value.map { |item| canonical(item) }
          when ::String
            raise Error.new(:invalid_document, "invalid UTF-8") unless value.encoding == Encoding::UTF_8 && value.valid_encoding?

            value
          when ::Integer, ::TrueClass, ::FalseClass, ::NilClass then value
          else
            raise Error.new(:invalid_document, "non-neutral value")
          end
        end

        private

        def validate_header(manifest)
          fail_with(:unsupported_version, "/manifest") unless manifest["manifest"] == 1
          unless manifest["schema_version"].is_a?(::Integer) && manifest["schema_version"] == @expected["schema_version"]
            fail_with(:unsupported_version, "/schema_version")
          end
          fail_with(:invalid_document, "/target") unless TARGETS.include?(manifest["target"])
          fail_with(:invalid_document, "/lml_checksum") unless digest?(manifest["lml_checksum"])
          unless manifest["generator_version"].is_a?(::String) && !manifest["generator_version"].empty?
            fail_with(:invalid_document, "/generator_version")
          end
          capabilities = manifest["capabilities"]
          unless capabilities.is_a?(::Array) && capabilities.all?(::String) &&
              capabilities == capabilities.sort.uniq
            fail_with(:invalid_document, "/capabilities")
          end
          validate_pins(manifest["corpora"], "corpora", "generation")
          validate_pins(manifest["dependencies"], "dependencies", "name")
        end

        def validate_pins(records, field, identity)
          fail_with(:invalid_document, "/#{field}") unless records.is_a?(::Array)
          names = records.map.with_index do |record, index|
            unless record.is_a?(::Hash) && record[identity].is_a?(::String) &&
                !record[identity].empty? && digest?(record["sha256"])
              fail_with(:invalid_document, "/#{field}/#{index}")
            end
            if field == "dependencies" && (!record["revision"].is_a?(::String) || record["revision"].empty?)
              fail_with(:invalid_document, "/#{field}/#{index}/revision")
            end
            record.fetch(identity)
          end
          fail_with(:invalid_document, "/#{field}") unless names == names.sort.uniq
        end

        def verify_files(records)
          unless records.is_a?(::Array) && !records.empty?
            fail_with(:invalid_document, "/files")
          end
          paths = records.map.with_index do |record, index|
            unless record.is_a?(::Hash) && digest?(record["sha256"])
              fail_with(:invalid_document, "/files/#{index}")
            end
            path = artifact_path(record["path"], index)
            actual = "sha256:#{Digest::SHA256.file(path).hexdigest}"
            fail_with(:checksum_mismatch, "/files/#{index}/sha256") unless actual == record["sha256"]
            record.fetch("path")
          end
          fail_with(:invalid_document, "/files") unless paths == paths.sort.uniq
        end

        def artifact_path(relative, index)
          location = "/files/#{index}/path"
          unless relative.is_a?(::String) && !relative.empty? &&
              !relative.include?("\\") && !relative.include?("\0") &&
              !relative.match?(/\A(?:[A-Za-z]:|\/)/) &&
              relative.split("/", -1).none? { |part| INVALID_PATH_PARTS.include?(part) }
            fail_with(:invalid_document, location)
          end
          path = @root.join(relative).realpath
          unless path.file? && path.to_s.start_with?("#{@root}#{File::SEPARATOR}")
            fail_with(:invalid_document, location)
          end
          path
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
          fail_with(:invalid_document, location)
        end

        def digest?(value)
          value.is_a?(::String) && DIGEST.match?(value)
        end

        def deep_freeze(value)
          case value
          when ::Hash then value.each do |key, item| 
            key.freeze
            deep_freeze(item)
          end
          when ::Array then value.each { |item| deep_freeze(item) }
          end
          value.freeze
        end

        def fail_with(reason, location)
          raise Error.new(reason, location)
        end
      end
    end
  end
end
