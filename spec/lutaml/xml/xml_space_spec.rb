# frozen_string_literal: true

require "spec_helper"

RSpec.describe "xml_space and w3c_attributes features" do
  describe "xml_space method" do
    let(:mapping) { Lutaml::Xml::Mapping.new }

    it "sets and returns @xml_space value when called with a value" do
      mapping.xml_space :preserve
      expect(mapping.xml_space).to eq(:preserve)
    end

    it "returns nil when xml_space not set" do
      expect(mapping.xml_space).to be_nil
    end

    it "preserve_whitespace? returns true when set to :preserve" do
      mapping.xml_space :preserve
      expect(mapping.preserve_whitespace?).to be(true)
    end

    it "preserve_whitespace? returns false when set to :default" do
      mapping.xml_space :default
      expect(mapping.preserve_whitespace?).to be(false)
    end

    it "preserve_whitespace? returns false when not set" do
      expect(mapping.preserve_whitespace?).to be(false)
    end
  end

  describe "w3c_attributes convenience method" do
    let(:mapping) { Lutaml::Xml::Mapping.new }

    it "creates attribute mappings for each provided attribute name" do
      mapping.w3c_attributes :lang, :space, :base

      lang_rule = mapping.find_by_to(:lang)
      space_rule = mapping.find_by_to(:space)
      base_rule = mapping.find_by_to(:base)

      expect(lang_rule).not_to be_nil
      expect(space_rule).not_to be_nil
      expect(base_rule).not_to be_nil
      expect(lang_rule.name).to eq("lang")
      expect(space_rule.name).to eq("space")
      expect(base_rule.name).to eq("base")
    end

    it "maps attribute name to the same attribute" do
      mapping.w3c_attributes :lang
      rule = mapping.find_by_to(:lang)

      expect(rule.to).to eq(:lang)
    end

    it "handles single attribute" do
      mapping.w3c_attributes :lang
      rule = mapping.find_by_to(:lang)

      expect(rule).not_to be_nil
    end
  end

  describe "xml_space with mixed_content" do
    let(:mapping) { Lutaml::Xml::Mapping.new }

    it "mixed_content sets @mixed_content and @ordered" do
      mapping.mixed_content

      expect(mapping.mixed_content?).to be(true)
      expect(mapping.ordered?).to be(true)
    end

    it "xml_space works independently from mixed_content" do
      mapping_instance = Lutaml::Xml::Mapping.new
      mapping_instance.xml_space :preserve

      expect(mapping_instance.xml_space).to eq(:preserve)
      expect(mapping_instance.mixed_content?).to be(false)
      expect(mapping_instance.preserve_whitespace?).to be(true)
    end

    it "both can be set together" do
      mapping.mixed_content
      mapping.xml_space :preserve

      expect(mapping.mixed_content?).to be(true)
      expect(mapping.preserve_whitespace?).to be(true)
    end
  end

  describe "xml_space serialization" do
    before do
      stub_const("XmlSpacePreserveModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "text"
          mixed_content
          xml_space :preserve
          map_content to: :content
        end
      end)

      stub_const("XmlSpaceDefaultModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "text"
          xml_space :default
          map_content to: :content
        end
      end)

      stub_const("XmlSpaceNoneModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string

        xml do
          element "text"
          mixed_content
          map_content to: :content
        end
      end)
    end

    after do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it "adds xml:space='preserve' when xml_space is :preserve" do
      model = XmlSpacePreserveModel.new(content: "Hello")
      xml = model.to_xml

      expect(xml).to include('xml:space="preserve"')
    end

    it "does not add xml:space attribute when xml_space is not set" do
      model = XmlSpaceNoneModel.new(content: "Hello")
      xml = model.to_xml

      expect(xml).not_to include("xml:space")
    end

    it "does not add xml:space='default' (attribute not added for :default)" do
      model = XmlSpaceDefaultModel.new(content: "Hello")
      xml = model.to_xml

      # xml_space :default is informational; the attribute is not auto-added
      # because default whitespace handling is the XML default behavior
      expect(xml).not_to include("xml:space")
    end
  end

  describe "w3c_attributes serialization" do
    before do
      stub_const("W3cAttributesModel", Class.new(Lutaml::Model::Serializable) do
        attribute :lang, Lutaml::Xml::W3c::XmlLangType
        attribute :space, Lutaml::Xml::W3c::XmlSpaceType
        attribute :base, Lutaml::Xml::W3c::XmlBaseType
        attribute :content, :string

        xml do
          element "p"
          w3c_attributes :lang, :space, :base
          map_content to: :content
        end
      end)
    end

    after do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it "serializes W3C attributes with proper namespace prefix" do
      model = W3cAttributesModel.new(
        content: "Hello",
        lang: "en",
        space: "preserve",
        base: "http://example.com/",
      )
      xml = model.to_xml

      expect(xml).to include('xml:lang="en"')
      expect(xml).to include('xml:space="preserve"')
      expect(xml).to include('xml:base="http://example.com/"')
    end

    it "serializes without W3C attributes when not set" do
      model = W3cAttributesModel.new(content: "Hello")
      xml = model.to_xml

      expect(xml).not_to include("xml:lang")
      expect(xml).not_to include("xml:space")
    end

    it "round-trips W3C attributes" do
      xml = '<p xml:lang="en" xml:space="preserve">Content</p>'
      model = W3cAttributesModel.from_xml(xml)

      expect(model.lang).to eq("en")
      expect(model.space).to eq("preserve")
      expect(model.content).to eq("Content")
    end
  end

  describe "xml_space with user-defined space attribute" do
    before do
      stub_const("UserDefinedSpaceModel", Class.new(Lutaml::Model::Serializable) do
        attribute :content, :string
        attribute :space, Lutaml::Xml::W3c::XmlSpaceType

        xml do
          element "text"
          mixed_content
          xml_space :preserve
          map_content to: :content
          map_attribute "space", to: :space
        end
      end)
    end

    after do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it "respects user-set space value over auto-added" do
      model = UserDefinedSpaceModel.new(content: "Hello", space: "default")
      xml = model.to_xml

      # User's value should take precedence
      expect(xml).to include('xml:space="default"')
      expect(xml).not_to include('xml:space="preserve"')
    end

    it "does not auto-add xml:space when user has defined space attribute" do
      # When user defines a space attribute, they control xml:space
      # Auto-adding is disabled regardless of the value
      model = UserDefinedSpaceModel.new(content: "Hello", space: nil)
      xml = model.to_xml

      # No xml:space should be added since user has control
      expect(xml).not_to include("xml:space")
    end
  end
end
