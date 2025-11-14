require "spec_helper"

RSpec.describe Lutaml::Model::Type::QName do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with prefixed QName string" do
      let(:value) { "xsd:string" }

      it { is_expected.to eq("xsd:string") }
    end

    context "with unprefixed QName string" do
      let(:value) { "elementName" }

      it { is_expected.to eq("elementName") }
    end

    context "with QName instance" do
      let(:qname_instance) { described_class.new("prefix:localName") }
      let(:value) { qname_instance }

      it { is_expected.to eq("prefix:localName") }
    end

    context "with complex prefix" do
      let(:value) { "my-prefix:localName" }

      it { is_expected.to eq("my-prefix:localName") }
    end

    context "with numeric characters" do
      let(:value) { "ns1:element123" }

      it { is_expected.to eq("ns1:element123") }
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with prefixed QName string" do
      let(:value) { "xs:anyType" }

      it { is_expected.to eq("xs:anyType") }
    end

    context "with QName instance" do
      let(:qname_instance) { described_class.new("prefix:name") }
      let(:value) { qname_instance }

      it { is_expected.to eq("prefix:name") }
    end
  end

  describe ".xsd_type" do
    it "returns xs:QName" do
      expect(described_class.xsd_type).to eq("xs:QName")
    end
  end

  describe ".from_parts" do
    context "with prefix and local_name" do
      subject(:qname) do
        described_class.from_parts(prefix: "xs", local_name: "string")
      end

      it "creates QName with prefix" do
        expect(qname.prefix).to eq("xs")
      end

      it "creates QName with local_name" do
        expect(qname.local_name).to eq("string")
      end

      it "creates correct string representation" do
        expect(qname.to_s).to eq("xs:string")
      end
    end

    context "with only local_name" do
      subject(:qname) { described_class.from_parts(local_name: "element") }

      it "has nil prefix" do
        expect(qname.prefix).to be_nil
      end

      it "has correct local_name" do
        expect(qname.local_name).to eq("element")
      end

      it "creates correct string representation" do
        expect(qname.to_s).to eq("element")
      end
    end

    context "with namespace_uri" do
      subject(:qname) do
        described_class.from_parts(
          prefix: "ex",
          local_name: "element",
          namespace_uri: "https://example.com",
        )
      end

      it "stores namespace_uri" do
        expect(qname.namespace_uri).to eq("https://example.com")
      end
    end
  end

  describe "#initialize" do
    context "with prefixed QName" do
      subject(:qname) { described_class.new("prefix:localName") }

      it "parses prefix correctly" do
        expect(qname.prefix).to eq("prefix")
      end

      it "parses local_name correctly" do
        expect(qname.local_name).to eq("localName")
      end

      it "has nil namespace_uri" do
        expect(qname.namespace_uri).to be_nil
      end
    end

    context "with unprefixed QName" do
      subject(:qname) { described_class.new("elementName") }

      it "has nil prefix" do
        expect(qname.prefix).to be_nil
      end

      it "parses local_name correctly" do
        expect(qname.local_name).to eq("elementName")
      end

      it "has nil namespace_uri" do
        expect(qname.namespace_uri).to be_nil
      end
    end

    context "with QName instance" do
      subject(:qname) { described_class.new(original) }

      let(:original) { described_class.new("xs:string") }

      it "copies prefix" do
        expect(qname.prefix).to eq("xs")
      end

      it "copies local_name" do
        expect(qname.local_name).to eq("string")
      end

      it "copies namespace_uri" do
        expect(qname.namespace_uri).to eq(original.namespace_uri)
      end
    end

    context "with multiple colons" do
      subject(:qname) { described_class.new("prefix:local:name") }

      it "splits at first colon only" do
        expect(qname.prefix).to eq("prefix")
        expect(qname.local_name).to eq("local:name")
      end
    end
  end

  describe "#to_s" do
    context "with prefixed QName" do
      let(:qname) { described_class.new("xs:element") }

      it "returns the original string" do
        expect(qname.to_s).to eq("xs:element")
      end
    end

    context "with unprefixed QName" do
      let(:qname) { described_class.new("element") }

      it "returns the original string" do
        expect(qname.to_s).to eq("element")
      end
    end
  end

  describe "integration with Serializable" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :ref_type, :qname
        attribute :target, :qname

        xml do
          root "reference"
          map_attribute "type", to: :ref_type
          map_element "target", to: :target
        end
      end
    end

    it "serializes QNames correctly" do
      instance = model_class.new(
        ref_type: "xsd:string",
        target: "ns:elementName",
      )
      xml = instance.to_xml
      expect(xml).to include('type="xsd:string"')
      expect(xml).to include("<target>ns:elementName</target>")
    end

    it "deserializes QNames correctly" do
      xml = '<reference type="xsd:int"><target>ns:element</target></reference>'
      instance = model_class.from_xml(xml)
      expect(instance.ref_type).to eq("xsd:int")
      expect(instance.target).to eq("ns:element")
    end

    it "handles unprefixed QNames" do
      instance = model_class.new(ref_type: "simple", target: "element")
      xml = instance.to_xml
      expect(xml).to include('type="simple"')
      expect(xml).to include("<target>element</target>")
    end

    it "handles nil QName" do
      instance = model_class.new(ref_type: nil)
      expect(instance.ref_type).to be_nil
    end
  end
end
