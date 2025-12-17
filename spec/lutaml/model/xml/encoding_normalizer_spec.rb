# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::Xml::EncodingNormalizer do
  describe ".normalize_to_utf8" do
    context "with nil or empty input" do
      it "returns nil for nil input" do
        expect(described_class.normalize_to_utf8(nil)).to be_nil
      end

      it "returns empty string for empty input" do
        result = described_class.normalize_to_utf8("")
        expect(result).to eq("")
      end
    end

    context "with UTF-8 input" do
      it "returns same string if already UTF-8" do
        content = "Hello UTF-8"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq(content)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "preserves UTF-8 Unicode characters" do
        content = "Unicode: © µ ∑ ∏ ​"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq(content)
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "with Shift_JIS input" do
      it "converts Shift_JIS to UTF-8" do
        # "手書き英字" in Shift_JIS
        shift_jis_content = "手書き英字".encode("Shift_JIS")
        expect(shift_jis_content.encoding).to eq(Encoding::Shift_JIS)

        result = described_class.normalize_to_utf8(shift_jis_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("手書き英字")
      end

      it "handles Shift_JIS with mixed content" do
        shift_jis_content = "text 手書き more text".encode("Shift_JIS")
        result = described_class.normalize_to_utf8(shift_jis_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("text 手書き more text")
      end
    end

    context "with ISO-8859-1 input" do
      it "converts ISO-8859-1 to UTF-8" do
        # Using characters in ISO-8859-1 range
        iso_content = "café résumé".encode("ISO-8859-1")
        expect(iso_content.encoding).to eq(Encoding::ISO_8859_1)

        result = described_class.normalize_to_utf8(iso_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("café résumé")
      end

      it "handles copyright and micro sign" do
        # © (U+00A9) and µ (U+00B5) are in ISO-8859-1
        iso_content = "© µ".encode("ISO-8859-1")
        result = described_class.normalize_to_utf8(iso_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("© µ")
      end
    end

    context "with ASCII-8BIT input" do
      it "converts ASCII-8BIT to UTF-8" do
        binary_content = "Hello".dup.force_encoding("ASCII-8BIT")
        result = described_class.normalize_to_utf8(binary_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("Hello")
      end
    end

    context "with various Unicode characters" do
      it "preserves copyright symbol ©" do
        content = "©"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq("©")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "preserves micro sign µ" do
        content = "µ"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq("µ")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "preserves summation ∑" do
        content = "∑"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq("∑")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "preserves product ∏" do
        content = "∏"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq("∏")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end

      it "preserves zero-width space ​" do
        content = "​"
        result = described_class.normalize_to_utf8(content)
        expect(result).to eq("​")
        expect(result.encoding).to eq(Encoding::UTF_8)
      end
    end

    context "with source_encoding parameter" do
      it "uses provided Encoding object" do
        shift_jis_content = "手書き".encode("Shift_JIS")
        result = described_class.normalize_to_utf8(
          shift_jis_content,
          source_encoding: Encoding::Shift_JIS
        )
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("手書き")
      end

      it "uses provided encoding name string" do
        iso_content = "café".encode("ISO-8859-1")
        result = described_class.normalize_to_utf8(
          iso_content,
          source_encoding: "ISO-8859-1"
        )
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("café")
      end

      it "falls back to content encoding if source_encoding is nil" do
        shift_jis_content = "手書き".encode("Shift_JIS")
        result = described_class.normalize_to_utf8(
          shift_jis_content,
          source_encoding: nil
        )
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to eq("手書き")
      end
    end

    context "with invalid byte sequences" do
      it "replaces invalid bytes with ?" do
        # Create invalid UTF-8 sequence
        invalid_content = "\xFF\xFE".dup.force_encoding("UTF-8")
        result = described_class.normalize_to_utf8(invalid_content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        # Result should be valid UTF-8 (replacement happened)
        expect(result.valid_encoding?).to be true
      end

      it "handles mixed valid and invalid content" do
        # Mix valid UTF-8 with invalid bytes
        content = "valid".dup.force_encoding("ASCII-8BIT") + "\xFF".dup.force_encoding("ASCII-8BIT")
        content.force_encoding("UTF-8")
        result = described_class.normalize_to_utf8(content)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to start_with("valid")
      end
    end

    context "error handling" do
      it "handles UndefinedConversionError gracefully" do
        # This should not raise, but fall back to force_encoding
        content = "\x80".dup.force_encoding("ASCII-8BIT")
        expect do
          result = described_class.normalize_to_utf8(content)
          expect(result.encoding).to eq(Encoding::UTF_8)
        end.not_to raise_error
      end

      it "handles InvalidByteSequenceError gracefully" do
        # Create content with invalid byte sequence for conversion
        content = "\xFF\xFE".dup.force_encoding("ISO-8859-1")
        expect do
          result = described_class.normalize_to_utf8(content)
          expect(result.encoding).to eq(Encoding::UTF_8)
        end.not_to raise_error
      end
    end

    context "round-trip conversions" do
      it "UTF-8 → Shift_JIS → UTF-8" do
        original = "手書き英字"
        shift_jis = original.encode("Shift_JIS")
        result = described_class.normalize_to_utf8(shift_jis)
        expect(result).to eq(original)
      end

      it "UTF-8 → ISO-8859-1 → UTF-8" do
        original = "café résumé"
        iso = original.encode("ISO-8859-1")
        result = described_class.normalize_to_utf8(iso)
        expect(result).to eq(original)
      end

      it "preserves content through multiple normalizations" do
        content = "Unicode: © µ ∑ ∏"
        result1 = described_class.normalize_to_utf8(content)
        result2 = described_class.normalize_to_utf8(result1)
        expect(result2).to eq(content)
        expect(result1.object_id).to eq(result2.object_id) # Same object returned
      end
    end
  end
end