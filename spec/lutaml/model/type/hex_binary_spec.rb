require "spec_helper"

RSpec.describe Lutaml::Model::Type::HexBinary do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with string value" do
      let(:value) { "48656c6c6f" }

      it { is_expected.to eq("48656c6c6f") }
    end

    context "with uppercase hex string" do
      let(:value) { "48656C6C6F" }

      it { is_expected.to eq("48656C6C6F") }
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

    context "with hex string" do
      let(:value) { "48656c6c6f" }

      it { is_expected.to eq("48656c6c6f") }
    end

    context "with empty string" do
      let(:value) { "" }

      it { is_expected.to eq("") }
    end
  end

  describe ".xsd_type" do
    it "returns xs:hexBinary" do
      expect(described_class.xsd_type).to eq("xs:hexBinary")
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
        result = described_class.encode("Hello")
        expect(result).to eq("48656c6c6f")
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
        expect(encoded).to eq("000102ff")
      end
    end

    context "with single byte" do
      it "encodes with leading zero" do
        expect(described_class.encode("\x0F")).to eq("0f")
      end
    end

    context "with all zeros" do
      it "encodes correctly" do
        expect(described_class.encode("\x00\x00")).to eq("0000")
      end
    end

    context "with all ones" do
      it "encodes correctly" do
        expect(described_class.encode("\xFF\xFF")).to eq("ffff")
      end
    end

    context "with unicode string" do
      it "encodes UTF-8 bytes" do
        unicode = "世"
        encoded = described_class.encode(unicode)
        expect(encoded).to be_a(String)
        expect(encoded.length).to be > 0
      end
    end
  end

  describe ".decode" do
    context "with nil value" do
      it "returns nil" do
        expect(described_class.decode(nil)).to be_nil
      end
    end

    context "with valid hex string" do
      it "decodes correctly" do
        decoded = described_class.decode("48656c6c6f")
        expect(decoded).to eq("Hello")
      end
    end

    context "with uppercase hex string" do
      it "decodes correctly" do
        decoded = described_class.decode("48656C6C6F")
        expect(decoded).to eq("Hello")
      end
    end

    context "with empty string" do
      it "returns empty string" do
        expect(described_class.decode("")).to eq("")
      end
    end

    context "with binary data" do
      it "decodes correctly" do
        decoded = described_class.decode("000102ff")
        expect(decoded.bytes).to eq([0, 1, 2, 255])
      end
    end

    context "with leading zeros" do
      it "decodes correctly" do
        decoded = described_class.decode("0f")
        expect(decoded).to eq("\x0F")
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
      original = "こんにちは"
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

    it "preserves empty string" do
      original = ""
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded).to eq(original)
    end

    it "preserves single byte" do
      original = "\x42"
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded).to eq(original)
    end

    it "preserves null bytes" do
      original = "\x00\x00\x00"
      encoded = described_class.encode(original)
      decoded = described_class.decode(encoded)
      expect(decoded).to eq(original)
    end
  end

  describe "integration with Serializable" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :hash_value, :hex_binary
        attribute :algorithm, :string

        xml do
          root "checksum"
          map_element "value", to: :hash_value
          map_attribute "algorithm", to: :algorithm
        end
      end
    end

    it "deserializes hex data correctly" do
      encoded = Lutaml::Model::Type::HexBinary.encode("Test")
      xml = %(<checksum algorithm="MD5"><value>#{encoded}</value></checksum>)

      instance = model_class.from_xml(xml)
      expect(instance.hash_value).to eq(encoded)
      expect(instance.algorithm).to eq("MD5")
    end
  end
end