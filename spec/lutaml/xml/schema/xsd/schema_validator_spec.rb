# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Lutaml::Xml::Schema::Xsd::SchemaValidator do
  describe "#initialize" do
    it "accepts version 1.0" do
      validator = described_class.new(version: "1.0")
      expect(validator.version).to eq("1.0")
    end

    it "accepts version 1.1" do
      validator = described_class.new(version: "1.1")
      expect(validator.version).to eq("1.1")
    end

    it "defaults to version 1.0" do
      validator = described_class.new
      expect(validator.version).to eq("1.0")
    end

    it "raises ArgumentError for invalid version" do
      expect do
        described_class.new(version: "2.0")
      end.to raise_error(ArgumentError, /Invalid XSD version/)
    end
  end

  describe "#validate" do
    let(:valid_xsd_1_0) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test"
                   elementFormDefault="qualified">
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
      XSD
    end

    let(:valid_xsd_1_1_with_assert) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test"
                   elementFormDefault="qualified">
          <xs:element name="root">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="value" type="xs:integer"/>
              </xs:sequence>
              <xs:assert test="value gt 0"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
      XSD
    end

    let(:invalid_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
        <!-- Missing closing tag -->
      XML
    end

    let(:non_xsd_document) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <root>
          <child>content</child>
        </root>
      XML
    end

    let(:wrong_namespace) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.example.com/wrong">
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
      XML
    end

    let(:no_namespace) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <schema>
          <element name="root" type="string"/>
        </schema>
      XML
    end

    context "with XSD 1.0 validator" do
      let(:validator) { described_class.new(version: "1.0") }

      it "validates a valid XSD 1.0 schema" do
        expect(validator.validate(valid_xsd_1_0)).to be true
      end

      it "raises error for invalid XML syntax" do
        expect do
          validator.validate(invalid_xml)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /Invalid XML syntax/)
      end

      it "raises error for non-XSD document" do
        expect do
          validator.validate(non_xsd_document)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /Not a valid XSD schema/)
      end

      it "raises error for wrong namespace" do
        expect do
          validator.validate(wrong_namespace)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /invalid namespace/)
      end

      it "raises error for missing namespace" do
        expect do
          validator.validate(no_namespace)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /must be in the XML Schema namespace/)
      end

      it "raises error for XSD 1.1 features (assert)" do
        expect do
          validator.validate(valid_xsd_1_1_with_assert)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /XSD 1.1 features.*xs:assert/)
      end
    end

    context "with XSD 1.1 validator" do
      let(:validator) { described_class.new(version: "1.1") }

      it "validates a valid XSD 1.0 schema" do
        expect(validator.validate(valid_xsd_1_0)).to be true
      end

      it "validates a valid XSD 1.1 schema with assert" do
        expect(validator.validate(valid_xsd_1_1_with_assert)).to be true
      end

      it "raises error for invalid XML syntax" do
        expect do
          validator.validate(invalid_xml)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /Invalid XML syntax/)
      end

      it "raises error for non-XSD document" do
        expect do
          validator.validate(non_xsd_document)
        end.to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError,
                           /Not a valid XSD schema/)
      end
    end
  end

  describe ".detect_version" do
    it "detects XSD 1.0 for basic schema" do
      schema = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
      XSD

      expect(described_class.detect_version(schema)).to eq("1.0")
    end

    it "detects XSD 1.1 when assert element is present" do
      schema = <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType>
              <xs:assert test="true()"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
      XSD

      expect(described_class.detect_version(schema)).to eq("1.1")
    end

    it "returns 1.0 for invalid XML" do
      expect(described_class.detect_version("<invalid")).to eq("1.0")
    end
  end

  describe "integration with Lutaml::Xml::Schema::Xsd.parse" do
    let(:valid_schema) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="http://example.com/test">
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
      XSD
    end

    let(:invalid_schema) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <root>
          <child>Not a schema</child>
        </root>
      XML
    end

    it "validates schema before parsing by default" do
      expect { Lutaml::Xml::Schema::Xsd.parse(valid_schema) }.not_to raise_error
    end

    it "allows disabling validation" do
      # When validation is disabled, it won't raise SchemaValidationError
      # It may either parse successfully or raise a different parsing error
      expect do
        Lutaml::Xml::Schema::Xsd.parse(invalid_schema, validate_schema: false)
      end.not_to raise_error(Lutaml::Xml::Schema::Xsd::SchemaValidationError)
    end
  end
end
