require "spec_helper"

RSpec.describe Lutaml::Model::Type::Base64Binary do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with string value" do
      let(:value) { "SGVsbG8gV29ybGQ=" }

      it { is_expected.to eq("SGVsbG8gV29ybGQ=") }
    end

    context "with already encoded base64 string" do
      let(:value) { "VGVzdCBEYXRh" }

      it { is_expected.to eq("VGVzdCBEYXRh") }
    end

    context "with empty string" do
      let(:value) { "" }

      it { is_expected.to eq("") }
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with base64 string" do
      let(:value) { "SGVsbG8gV29ybGQ=" }

      it { is_expected.to eq("SGVsbG8gV29ybGQ=") }
    end

    context "with empty string" do
      let(:value) { "" }

      it { is_expected.to eq("") }
    end
  end

  describe ".xsd_type" do
    it "returns xs:base64Binary" do
      expect(described_class.xsd_type).to eq("xs:base64Binary")
    end
  end

  describe ".encode" do
    context "with nil value" do
      it "returns nil" do
        expect(described_class.encode(nil)).to be_nil
      end
    end

    context "with simple string" do
      it "encodes correctly" do
        result = described_class.encode("Hello World")
        expect(result).to eq("SGVsbG8gV29ybGQ=")
      end
    end

    context "with empty string" do
      it "returns empty string" do
        expect(described_class.encode("")).to eq("")
      end
    end

    context "with binary data" do
      it "encodes correctly" do
        binary_data = "\x00\x01\x02\xFF".force_encoding("ASCII-8BIT")
        encoded = described_class.encode(binary_data)
        expect(encoded).to be_a(String)
        expect(encoded.length).to be > 0
      end
    end

    context "with unicode string" do
      it "encodes correctly" do
        unicode = "Hello 世界"
        encoded = described_class.encode(unicode)
        expect(encoded).to be_a(String)
      end
    end

    context "with special characters" do
      it "encodes newlines" do
        text = "Line 1\nLine 2"
        encoded = described_class.encode(text)
        expect(encoded).to be_a(String)
      end

      it "encodes tabs" do
        text = "Col1\tCol2"
        encoded = described_class.encode(text)
        expect(encoded).to be_a(String)
      end
    end
  end

  describe ".decode" do
    context "with nil value" do
      it "returns nil" do
        expect(described_class.decode(nil)).to be_nil
      end
    end

    context "with valid base64 string" do
      it "decodes correctly" do
        decoded = described_class.decode("SGVsbG8gV29ybGQ=")
        expect(decoded).to eq("Hello World")
      end
    end

    context "with empty string" do
      it "returns empty string" do
        expect(described_class.decode("")).to eq("")
      end
    end

    context "with binary data" do
      it "decodes correctly" do
        original = "\x00\x01\x02\xFF".force_encoding("ASCII-8BIT")
        encoded = described_class.encode(original)
        decoded = described_class.decode(encoded)
        expect(decoded.bytes).to eq(original.bytes)
      end
    end
  end

  describe "round-trip encoding/decoding" do
    it "preserves simple text" do
      original = "Hello, World!"
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded).to eq(original)
    end

    it "preserves unicode text" do
      original = "こんにちは世界"
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded.bytes).to eq(original.bytes)
    end

    it "preserves binary data" do
      original = (0..255).map(&:chr).join.force_encoding("ASCII-8BIT")
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded.bytes).to eq(original.bytes)
    end

    it "preserves whitespace" do
      original = "  Space  \n  Newline  \t  Tab  "
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded).to eq(original)
    end

    it "preserves empty string" do
      original = ""
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded).to eq(original)
    end
  end

  describe "integration with Serializable" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :content, :base64_binary
        attribute :filename, :string

        xml do
          element "attachment"
          map_element "content", to: :content
          map_attribute "filename", to: :filename
        end
      end
    end

    it "deserializes base64 data correctly" do
      encoded = described_class.encode("Test Data")
      xml = %(<attachment filename="test.txt"><content>#{encoded}</content></attachment>)

      instance = model_class.from_xml(xml)
      expect(instance.content).to eq(encoded)
      expect(instance.filename).to eq("test.txt")
    end
  end
end
