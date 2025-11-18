require "spec_helper"

RSpec.describe Lutaml::Model::Type::Uri do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with valid URI string" do
      let(:value) { "https://example.com/path" }

      it { is_expected.to eq("https://example.com/path") }
    end

    context "with URI object" do
      let(:value) { URI("https://example.com/path") }

      it { is_expected.to eq(URI("https://example.com/path")) }
    end

    context "with HTTP URI" do
      let(:value) { "http://example.com" }

      it { is_expected.to eq("http://example.com") }
    end

    context "with HTTPS URI" do
      let(:value) { "https://example.com" }

      it { is_expected.to eq("https://example.com") }
    end

    context "with FTP URI" do
      let(:value) { "ftp://ftp.example.com/file.txt" }

      it { is_expected.to eq("ftp://ftp.example.com/file.txt") }
    end

    context "with file URI" do
      let(:value) { "file:///path/to/file.xml" }

      it { is_expected.to eq("file:///path/to/file.xml") }
    end

    context "with mailto URI" do
      let(:value) { "mailto:user@example.com" }

      it { is_expected.to eq("mailto:user@example.com") }
    end

    context "with URI containing query parameters" do
      let(:value) { "https://example.com/path?param=value&other=123" }

      it { is_expected.to eq("https://example.com/path?param=value&other=123") }
    end

    context "with URI containing fragment" do
      let(:value) { "https://example.com/path#section" }

      it { is_expected.to eq("https://example.com/path#section") }
    end

    context "with URI containing special characters" do
      let(:value) { "https://example.com/path%20with%20spaces" }

      it { is_expected.to eq("https://example.com/path%20with%20spaces") }
    end

    context "with relative URI" do
      let(:value) { "/relative/path" }

      it { is_expected.to eq("/relative/path") }
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with URI string" do
      let(:value) { "https://example.com" }

      it { is_expected.to eq("https://example.com") }
    end

    context "with URI object" do
      let(:value) { URI("https://example.com/path") }

      it { is_expected.to eq("https://example.com/path") }
    end

    context "with complex URI" do
      let(:value) { "https://user:pass@example.com:8080/path?query=value#fragment" }

      it { is_expected.to eq("https://user:pass@example.com:8080/path?query=value#fragment") }
    end
  end

  describe ".xsd_type" do
    it "returns xs:anyURI" do
      expect(described_class.xsd_type).to eq("xs:anyURI")
    end
  end

  describe ".valid_uri?" do
    context "with valid URI" do
      it "returns true for HTTP URL" do
        expect(described_class.valid_uri?("https://example.com")).to be true
      end

      it "returns true for file URI" do
        expect(described_class.valid_uri?("file:///path/to/file")).to be true
      end

      it "returns true for mailto URI" do
        expect(described_class.valid_uri?("mailto:user@example.com")).to be true
      end
    end

    context "with invalid URI" do
      it "returns false for malformed URI" do
        expect(described_class.valid_uri?("http://[invalid")).to be false
      end

      it "returns false for URI with spaces" do
        expect(described_class.valid_uri?("http://example.com/path with spaces")).to be false
      end
    end
  end

  describe "integration with Serializable" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :homepage, :uri
        attribute :location, :uri

        xml do
          root "resource"
          map_element "homepage", to: :homepage
          map_attribute "location", to: :location
        end
      end
    end

    it "serializes URIs correctly" do
      instance = model_class.new(
        homepage: "https://example.com/page",
        location: "https://example.com/schema.xsd",
      )
      xml = instance.to_xml
      expect(xml).to include("<homepage>https://example.com/page</homepage>")
      expect(xml).to include('location="https://example.com/schema.xsd"')
    end

    it "deserializes URIs correctly" do
      xml = '<resource location="https://example.com/schema.xsd"><homepage>https://example.com</homepage></resource>'
      instance = model_class.from_xml(xml)
      expect(instance.homepage).to eq("https://example.com")
      expect(instance.location).to eq("https://example.com/schema.xsd")
    end

    it "handles nil URI" do
      instance = model_class.new(homepage: nil)
      expect(instance.homepage).to be_nil
    end
  end
end
