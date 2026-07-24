# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "validate_xml_with" do
  let(:schema_path) do
    File.expand_path("../../fixtures/xml/validate_xml_with_person.xsd",
                     __dir__)
  end

  before do
    path = schema_path
    stub_const("XsdValidatedPerson",
               Class.new(Lutaml::Model::Serializable) do
                 attribute :name, :string
                 attribute :age, :string

                 xml do
                   element "person"
                   map_element "name", to: :name
                   map_element "age", to: :age
                 end

                 validate_xml_with path
               end)
  end

  context "when the generated XML conforms to the schema" do
    let(:person) { XsdValidatedPerson.new(name: "Alice", age: "30") }

    it "returns no errors from validate" do
      expect(person.validate).to be_empty
    end

    it "does not raise on validate!" do
      expect { person.validate! }.not_to raise_error
    end
  end

  context "when the generated XML violates the schema" do
    let(:person) { XsdValidatedPerson.new(name: "Alice", age: "abc") }

    it "collects schema validation errors" do
      errors = person.validate

      expect(errors).to all(
        be_a(Lutaml::Xml::Error::SchemaValidationError),
      )
      expect(errors.first.message).to include(schema_path)
    end

    it "raises ValidationError with the schema message on validate!" do
      expect { person.validate! }.to raise_error(
        Lutaml::Model::ValidationError,
        /age/,
      )
    end
  end

  describe ".validate_xml / .validate_xml!" do
    let(:valid_xml) do
      "<person><name>Alice</name><age>30</age></person>"
    end
    let(:invalid_xml) do
      "<person><name>Alice</name><age>abc</age></person>"
    end

    it "returns no errors for a conforming raw XML string" do
      expect(XsdValidatedPerson.validate_xml(valid_xml)).to be_empty
    end

    it "collects errors for a non-conforming raw XML string" do
      errors = XsdValidatedPerson.validate_xml(invalid_xml)

      expect(errors).to all(
        be_a(Lutaml::Xml::Error::SchemaValidationError),
      )
    end

    it "raises ValidationError for a non-conforming raw XML string" do
      expect do
        XsdValidatedPerson.validate_xml!(invalid_xml)
      end.to raise_error(Lutaml::Model::ValidationError, /age/)
    end

    it "raises a parse error for malformed XML instead of recovering" do
      expect do
        XsdValidatedPerson.validate_xml("<person><name>Alice</name>")
      end.to raise_error(Nokogiri::XML::SyntaxError)
    end
  end

  context "with schema path inheritance" do
    before do
      stub_const("XsdValidatedEmployee", Class.new(XsdValidatedPerson))
      stub_const("XsdAugmentedEmployee",
                 Class.new(XsdValidatedPerson) do
                   validate_xml_with "extra/employee.xsd"
                 end)
    end

    it "subclasses inherit the parent's schema" do
      employee = XsdValidatedEmployee.new(name: "Bob", age: "abc")

      expect(employee.validate).not_to be_empty
    end

    it "a subclass macro call appends parent-first" do
      expect(XsdAugmentedEmployee.xml_schema_paths).to eq(
        [schema_path, File.expand_path("extra/employee.xsd", __dir__)],
      )
    end

    it "does not leak child paths back to the parent" do
      expect(XsdValidatedPerson.xml_schema_paths).to eq([schema_path])
    end
  end

  context "with a schema path relative to the declaring file" do
    before do
      stub_const("RelativeSchemaPerson",
                 Class.new(Lutaml::Model::Serializable) do
                   attribute :name, :string
                   attribute :age, :string

                   xml do
                     element "person"
                     map_element "name", to: :name
                     map_element "age", to: :age
                   end

                   validate_xml_with(
                     "../../fixtures/xml/validate_xml_with_person.xsd",
                   )
                 end)
    end

    it "resolves the schema next to the declaring file, not the CWD" do
      Dir.chdir(Dir.tmpdir) do
        person = RelativeSchemaPerson.new(name: "Alice", age: "abc")

        expect(person.validate).not_to be_empty
      end
    end
  end

  context "when no schema is configured" do
    before do
      stub_const("PlainPerson", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          element "person"
          map_element "name", to: :name
        end
      end)
    end

    it "validates without touching XSD machinery" do
      expect(PlainPerson.new(name: "Alice").validate).to be_empty
    end
  end

  context "when the schema file does not exist" do
    before do
      stub_const("MissingSchemaPerson",
                 Class.new(Lutaml::Model::Serializable) do
                   attribute :name, :string

                   xml do
                     element "person"
                     map_element "name", to: :name
                   end

                   validate_xml_with "nonexistent/schema.xsd"
                 end)
    end

    it "raises a configuration-level error" do
      expect do
        MissingSchemaPerson.new(name: "Alice").validate
      end.to raise_error(Errno::ENOENT)
    end
  end
end
