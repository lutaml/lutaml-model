# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # EncodingNormalizer ensures all XML text content is normalized to UTF-8
      # internally, regardless of source encoding or adapter used.
      #
      # This provides:
      # - Consistent developer experience across adapters
      # - UTF-8 as internal encoding (Ruby's default)
      # - Ability to output in any encoding on serialization
      #
      # @example Normalize Shift_JIS to UTF-8
      #   content = "手書き英字".encode("Shift_JIS")
      #   normalized = EncodingNormalizer.normalize_to_utf8(content)
      #   normalized.encoding # => Encoding::UTF_8
      #
      class EncodingNormalizer
        # Normalize text content to UTF-8 for internal consistency
        #
        # @param content [String] Text content from XML adapter
        # @param source_encoding [String, Encoding, nil] Source encoding if known
        # @return [String] UTF-8 encoded string, or original if nil/empty
        def self.normalize_to_utf8(content, source_encoding: nil)
          return content if content.nil? || content.empty?

          # Return content if already valid UTF-8
          if content.encoding == Encoding::UTF_8 && content.valid_encoding?
            return content
          end

          # Determine source encoding
          encoding = resolve_encoding(content, source_encoding)

          # Convert to UTF-8
          content.encode(Encoding::UTF_8, encoding,
                        invalid: :replace,
                        undef: :replace,
                        replace: "?")
        rescue Encoding::UndefinedConversionError,
               Encoding::InvalidByteSequenceError => e
          # Fallback: force UTF-8 encoding and scrub invalid bytes
          content.force_encoding(Encoding::UTF_8).scrub("?")
        end

        private_class_method def self.resolve_encoding(content, source_encoding)
          return source_encoding if source_encoding.is_a?(Encoding)
          return Encoding.find(source_encoding) if source_encoding.is_a?(String)

          content.encoding
        end
      end
    end
  end
end