require "spec_helper"

RSpec.describe Lutaml::Xml::Type::ValueXmlMapping do
  let(:test_namespace) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "https://example.com/test"
      prefix_default "test"
    end
  end

  let(:other_namespace) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "https://example.com/other"
      prefix_default "other"
    end
  end

  describe "#namespace" do
    it "sets and gets namespace class" do
      mapping = described_class.new
      mapping.namespace(test_namespace)
      expect(mapping.namespace_class).to eq(test_namespace)
    end

    it "raises error for non-XmlNamespace class" do
      mapping = described_class.new
      expect do
        mapping.namespace(String)
      end.to raise_error(Lutaml::Xml::Error::InvalidNamespaceError, /XmlNamespace/)
    end
  end

  describe "#xsd_type" do
    context "with Symbol" do
      it "resolves :string to xs:string" do
        mapping = described_class.new
        mapping.xsd_type(:string)
        expect(mapping.xsd_type_name).to eq("xs:string")
      end

      it "resolves :integer to xs:integer" do
        mapping = described_class.new
        mapping.xsd_type(:integer)
        expect(mapping.xsd_type_name).to eq("xs:integer")
      end

      it "resolves :date to xs:date" do
        mapping = described_class.new
        mapping.xsd_type(:date)
        expect(mapping.xsd_type_name).to eq("xs:date")
      end

      it "raises error for unknown symbol" do
        mapping = described_class.new
        expect do
          mapping.xsd_type(:unknown_type)
        end.to raise_error(ArgumentError, /Unknown type symbol/)
      end
    end

    context "with Type class" do
      it "extracts default_xsd_type from String type" do
        mapping = described_class.new
        mapping.xsd_type(Lutaml::Model::Type::String)
        expect(mapping.xsd_type_name).to eq("xs:string")
      end

      it "extracts default_xsd_type from Integer type" do
        mapping = described_class.new
        mapping.xsd_type(Lutaml::Model::Type::Integer)
        expect(mapping.xsd_type_name).to eq("xs:integer")
      end

      it "extracts default_xsd_type from Date type" do
        mapping = described_class.new
        mapping.xsd_type(Lutaml::Model::Type::Date)
        expect(mapping.xsd_type_name).to eq("xs:date")
      end

      it "raises error for class without default_xsd_type" do
        mapping = described_class.new
        expect do
          mapping.xsd_type(String)
        end.to raise_error(ArgumentError, /must inherit from Lutaml::Model::Type::Value/)
      end
    end

    context "with invalid type" do
      it "raises error for String" do
        mapping = described_class.new
        expect do
          mapping.xsd_type("xs:string")
        end.to raise_error(ArgumentError, /must be a Symbol or Class/)
      end

      it "raises error for other types" do
        mapping = described_class.new
        expect do
          mapping.xsd_type(123)
        end.to raise_error(ArgumentError, /must be a Symbol or Class/)
      end
    end
  end

  describe "#namespace_uri" do
    it "returns URI from namespace class" do
      mapping = described_class.new
      mapping.namespace(test_namespace)
      expect(mapping.namespace_uri).to eq("https://example.com/test")
    end

    it "returns nil when no namespace is set" do
      mapping = described_class.new
      expect(mapping.namespace_uri).to be_nil
    end
  end

  describe "#namespace_prefix" do
    it "returns prefix from namespace class" do
      mapping = described_class.new
      mapping.namespace(test_namespace)
      expect(mapping.namespace_prefix).to eq("test")
    end

    it "returns nil when no namespace is set" do
      mapping = described_class.new
      expect(mapping.namespace_prefix).to be_nil
    end
  end

  describe "#deep_dup" do
    it "creates a deep copy of the mapping" do
      mapping = described_class.new
      mapping.namespace(test_namespace)
      mapping.xsd_type(:string)

      dup_mapping = mapping.deep_dup

      expect(dup_mapping.namespace_class).to eq(test_namespace)
      expect(dup_mapping.xsd_type_name).to eq("xs:string")

      # Verify it's a copy, not the same object
      expect(dup_mapping).not_to be(mapping)
    end

    it "allows modifying the copy without affecting the original" do
      mapping = described_class.new
      mapping.namespace(test_namespace)
      mapping.xsd_type(:string)

      dup_mapping = mapping.deep_dup
      dup_mapping.namespace(other_namespace)
      dup_mapping.xsd_type(:integer)

      expect(mapping.namespace_class).to eq(test_namespace)
      expect(mapping.xsd_type_name).to eq("xs:string")
      expect(dup_mapping.namespace_class).to eq(other_namespace)
      expect(dup_mapping.xsd_type_name).to eq("xs:integer")
    end
  end
end
