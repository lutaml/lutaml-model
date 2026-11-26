# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe "DSL (.lutaml) parsing via Lutaml::Lml::Parser" do
  def parse_dsl(fixture_name)
    Lutaml::Lml.parse(File.new(fixtures_path("dsl/#{fixture_name}")))
  end

  describe "simple diagram without attributes" do
    let(:doc) { parse_dsl("diagram.lutaml") }

    it "creates a Lutaml::Lml::Document" do
      expect(doc).to be_instance_of(Lutaml::Lml::Document)
    end
  end

  describe "diagram with attributes" do
    let(:doc) { parse_dsl("diagram_attributes.lutaml") }

    it "sets document metadata", :aggregate_failures do
      expect(doc).to be_instance_of(Lutaml::Lml::Document)
      expect(doc.title).to eq("my diagram, another symbols: text.")
      expect(doc.caption)
        .to(eq("Block elements of StandardDocument, adapted from " \
               "BasicDocument. Another - symbol"))
      expect(doc.fontname).to eq("Arial")
    end
  end

  describe "multiply classes entries" do
    let(:doc) { parse_dsl("diagram_multiply_classes.lutaml") }

    it "creates dependent classes", :aggregate_failures do
      classes = doc.classes
      expect(doc).to be_instance_of(Lutaml::Lml::Document)
      expect(classes.length).to eq(4)
      expect(by_name(classes, "NamespacedClass").stereotype).to eq(["MyNamespace"])
    end
  end

  describe "class with fields" do
    let(:doc) { parse_dsl("diagram_class_fields.lutaml") }

    it "creates the correct number of attributes", :aggregate_failures do
      classes = doc.classes
      expect(by_name(classes, "Component").attributes).to be_nil
      expect(by_name(classes, "AddressClassProfile")
              .attributes.length).to eq(1)
      expect(by_name(classes, "AttributeProfile")
              .attributes.length).to eq(13)
      expect(by_name(classes, "AttributeProfile")
              .attributes.map(&:name))
        .to(eq(["imlicistAttributeProfile",
                "attributeProfile",
                "attributeProfile1",
                "privateAttributeProfile",
                "friendlyAttributeProfile",
                "friendlyAttributeProfile1",
                "protectedAttributeProfile",
                "type/text",
                "slashType",
                "application/docbook+xml",
                "application/tei+xml",
                "text/x-asciidoc",
                "application/x-isodoc+xml"]))
    end

    it "sets the correct visibility on attributes", :aggregate_failures do
      attributes = by_name(doc.classes, "AttributeProfile").attributes
      expect(by_name(attributes, "imlicistAttributeProfile").visibility)
        .to be_nil
      expect(by_name(attributes, "imlicistAttributeProfile").stereotype)
        .to be_empty
      expect(by_name(attributes, "attributeProfile").visibility)
        .to eq("public")
      expect(by_name(attributes, "attributeProfile").stereotype)
        .to eq(["BasicDocument"])
      expect(by_name(attributes, "attributeProfile1").visibility)
        .to eq("public")
      expect(by_name(attributes, "attributeProfile1").stereotype)
        .to eq(["BasicDocument"])
      expect(by_name(attributes, "privateAttributeProfile").visibility)
        .to eq("private")
      expect(by_name(attributes, "friendlyAttributeProfile").visibility)
        .to eq("package")
      expect(by_name(attributes, "friendlyAttributeProfile").stereotype)
        .to eq(["Type"])
      expect(by_name(attributes, "protectedAttributeProfile").visibility)
        .to eq("protected")
    end
  end

  describe "association blocks" do
    let(:doc) { parse_dsl("diagram_class_assocation.lutaml") }

    it "creates the correct number of associations" do
      expect(doc.associations.length).to eq(3)
    end

    context "bidirectional association" do
      subject(:association) do
        by_name(doc.associations, "BidirectionalAsscoiation")
      end

      it "sets correct attributes", :aggregate_failures do
        expect(association.owner_end_type).to(eq("aggregation"))
        expect(association.member_end_type).to(eq("direct"))
        expect(association.owner_end).to(eq("AddressClassProfile"))
        expect(association.owner_end_attribute_name)
          .to(eq("addressClassProfile"))
        expect(association.member_end).to(eq("AttributeProfile"))
        expect(association.member_end_attribute_name)
          .to(eq("attributeProfile"))
        expect(association.member_end_cardinality.min).to(eq("0"))
        expect(association.member_end_cardinality.max).to(eq("*"))
      end
    end

    context "direct association" do
      subject(:association) do
        by_name(doc.associations, "DirectAsscoiation")
      end

      it "sets correct attributes", :aggregate_failures do
        expect(association.owner_end_type).to(be_nil)
        expect(association.member_end_type).to(eq("direct"))
        expect(association.owner_end).to(eq("AddressClassProfile"))
        expect(association.owner_end_attribute_name).to(be_nil)
        expect(association.member_end).to(eq("AttributeProfile"))
        expect(association.member_end_attribute_name)
          .to(eq("attributeProfile"))
        expect(association.member_end_cardinality).to(be_nil)
      end
    end

    context "reverse association" do
      subject(:association) do
        by_name(doc.associations, "ReverseAsscoiation")
      end

      it "sets correct attributes", :aggregate_failures do
        expect(association.owner_end_type).to(eq("aggregation"))
        expect(association.member_end_type).to(be_nil)
        expect(association.owner_end).to(eq("AddressClassProfile"))
        expect(association.owner_end_attribute_name)
          .to(eq("addressClassProfile"))
        expect(association.member_end).to(eq("AttributeProfile"))
        expect(association.member_end_attribute_name).to(be_nil)
        expect(association.member_end_cardinality).to(be_nil)
      end
    end
  end

  describe "data_types entries" do
    let(:doc) { parse_dsl("diagram_data_types.lutaml") }

    it "generates correct enums", :aggregate_failures do
      enums = doc.enums
      expect(by_name(enums, "MyEnum").attributes).to be_empty
      expect(by_name(enums, "AddressClassProfile")
              .attributes.length).to eq(1)
      expect(by_name(enums, "Profile")
              .attributes.length).to eq(5)
    end

    it "generates correct data_types" do
      data_types = doc.data_types
      expect(by_name(data_types, "Banking Information")
              .attributes.map(&:name))
        .to(eq(["art code", "CCT Number"]))
    end

    it "generates correct primitives" do
      expect(by_name(doc.primitives, "Integer")).not_to be_nil
    end
  end

  describe "concept model" do
    let(:doc) { parse_dsl("diagram_concept_model.lutaml") }

    it "generates correct class/enums/associations", :aggregate_failures do
      expect(doc.classes.length).to(eq(9))
      expect(doc.enums.length).to(eq(3))
      expect(doc.associations.length).to(eq(16))
    end

    it "generates correct attributes", :aggregate_failures do
      attributes = by_name(doc.classes, "ExpressionDesignation").attributes
      expect(attributes.length).to(eq(5))
      expect(attributes.map(&:name))
        .to(eq(%w[text language script pronunciation grammarInfo]))
      expect(attributes.map(&:type))
        .to(eq(["GlossaristTextElementType",
                "Iso639ThreeCharCode",
                "Iso15924Code",
                "LocalizedString",
                "GrammarInfo"]))
    end
  end

  describe "include directives" do
    let(:doc) { parse_dsl("diagram_includes.lutaml") }

    it "includes supplied files", :aggregate_failures do
      expect(doc.classes.map(&:name))
        .to(eq(%w[Foo Doo Koo AttributeProfile]))
      expect(by_name(doc.classes, "AttributeProfile")
              .attributes.map(&:name))
        .to eq(["imlicistAttributeProfile", "attributeProfile"])
    end
  end

  describe "comments" do
    let(:doc) { parse_dsl("diagram_comments.lutaml") }

    it "creates comments for document and classes", :aggregate_failures do
      expect(doc.comments).to(eq(["My comment",
                                  "this is multiline\n    comment with " \
                                  "{} special\n    chars/\n\n    +-|/"]))
      expect(doc.classes.last.comments)
        .to(eq(["this is attribute comment",
                "this is another comment line\n    with multiply lines"]))
    end
  end

  describe "definitions" do
    let(:doc) { parse_dsl("diagram_definitions.lutaml") }
    let(:class_definition) do
      "this is multiline with `ascidoc`\ncomments\nand list\n{foo} {name}"
    end
    let(:attribute_definition) do
      "this is attribute definition\nwith multiply lines" \
        "\n{foo} {name}\nend definition"
    end

    it "sets definitions on classes and attributes", :aggregate_failures do
      expect(by_name(doc.classes, "AddressClassProfile").definition)
        .to(eq(class_definition))
      expect(by_name(doc.classes, "AttributeProfile")
              .attributes
              .first
              .definition)
        .to(eq(attribute_definition))
    end
  end

  describe "edge cases" do
    it "parses blank definitions without error" do
      expect { parse_dsl("diagram_blank_definion.lutaml") }.not_to raise_error
    end

    it "parses blank entities without error" do
      expect { parse_dsl("diagram_blank_entities.lutaml") }.not_to raise_error
    end

    it "raises on non-existing include (no silent skipping)" do
      expect { parse_dsl("diagram_non_existing_include.lutaml") }
        .to raise_error(Lutaml::Lml::Error, /cannot read include/)
    end

    it "parses commented preprocessor lines without error" do
      expect { parse_dsl("diagram_commented_includes.lutaml") }.not_to raise_error
    end
  end

  describe "broken lutaml file" do
    it "raises ParsingError with line information" do
      expect { parse_dsl("broken_diagram.lutaml") }
        .to(raise_error(Lutaml::Lml::ParsingError,
                        /at line 25 char 32/))
    end
  end
end
