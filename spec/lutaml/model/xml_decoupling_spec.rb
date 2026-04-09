# frozen_string_literal: true

require "spec_helper"

# Integration specs verifying XML is properly decoupled from core model.
#
# These specs ensure that:
# 1. Core model functionality works independently of XML
# 2. XML functionality is properly registered via FormatRegistry
# 3. The prepend/hook mechanism works correctly
# 4. Type serializers are format-specific and registered dynamically
# 5. Backward compatibility aliases still work
RSpec.describe "XML decoupling from core model" do
  # A minimal model using only key-value formats (no XML block)
  let(:key_value_only_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :active, :boolean

      json do
        map "name", to: :name
        map "age", to: :age
        map "active", to: :active
      end

      yaml do
        map "name", to: :name
        map "age", to: :age
        map "active", to: :active
      end

      toml do
        map "name", to: :name
        map "age", to: :age
        map "active", to: :active
      end
    end
  end

  # A model using all formats including XML
  let(:full_format_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :title, :string
      attribute :count, :integer

      json do
        map "title", to: :title
        map "count", to: :count
      end

      yaml do
        map "title", to: :title
        map "count", to: :count
      end

      xml do
        root "item"
        map_element "title", to: :title
        map_element "count", to: :count
      end
    end
  end

  describe "FormatRegistry" do
    it "has XML registered as a format" do
      expect(Lutaml::Model::FormatRegistry.registered?(:xml)).to be true
    end

    it "has key-value formats registered" do
      %i[json yaml toml hash].each do |fmt|
        expect(Lutaml::Model::FormatRegistry.registered?(fmt)).to be true
      end
    end

    it "marks XML as a non-key-value format" do
      expect(Lutaml::Model::FormatRegistry.key_value?(:xml)).to be false
    end

    it "marks JSON, YAML, TOML, Hash as key-value formats" do
      %i[json yaml toml hash].each do |fmt|
        expect(Lutaml::Model::FormatRegistry.key_value?(fmt)).to be true
      end
    end

    it "provides a mapping class for XML" do
      expect(Lutaml::Model::FormatRegistry.mappings_class_for(:xml)).not_to be_nil
    end

    it "provides a transformer for XML" do
      expect(Lutaml::Model::FormatRegistry.transformer_for(:xml)).not_to be_nil
    end

    it "provides an adapter loader for XML" do
      expect(Lutaml::Model::FormatRegistry.adapter_loader_for(:xml)).not_to be_nil
    end
  end

  describe "Config" do
    it "does not include :xml in AVAILABLE_FORMATS constant" do
      expect(Lutaml::Model::Configuration::AVAILABLE_FORMATS).not_to include(:xml)
    end

    it "does not include XML in static ADAPTERS hash" do
      expect(Lutaml::Model::Configuration::ADAPTERS).not_to have_key(:xml)
    end

    it "allows setting XML adapter via Config" do
      expect { Lutaml::Model::Config.xml_adapter }.not_to raise_error
    end
  end

  describe "key-value serialization without XML" do
    it "serializes to JSON" do
      instance = key_value_only_class.new(name: "Alice", age: 30, active: true)
      json = instance.to_json
      parsed = JSON.parse(json)

      expect(parsed["name"]).to eq("Alice")
      expect(parsed["age"]).to eq(30)
      expect(parsed["active"]).to be(true)
    end

    it "deserializes from JSON" do
      json = '{"name":"Bob","age":25,"active":false}'
      instance = key_value_only_class.from_json(json)

      expect(instance.name).to eq("Bob")
      expect(instance.age).to eq(25)
      expect(instance.active).to be(false)
    end

    it "round-trips through JSON" do
      original = key_value_only_class.new(name: "Charlie", age: 40,
                                          active: true)
      restored = key_value_only_class.from_json(original.to_json)

      expect(restored.name).to eq(original.name)
      expect(restored.age).to eq(original.age)
      expect(restored.active).to eq(original.active)
    end

    it "serializes to YAML" do
      instance = key_value_only_class.new(name: "Diana", age: 35, active: true)
      yaml_str = instance.to_yaml
      parsed = YAML.safe_load(yaml_str)

      expect(parsed["name"]).to eq("Diana")
      expect(parsed["age"]).to eq(35)
      expect(parsed["active"]).to be(true)
    end

    it "deserializes from YAML" do
      yaml_str = "---\nname: Eve\nage: 28\nactive: false\n"
      instance = key_value_only_class.from_yaml(yaml_str)

      expect(instance.name).to eq("Eve")
      expect(instance.age).to eq(28)
      expect(instance.active).to be(false)
    end

    it "round-trips through YAML" do
      original = key_value_only_class.new(name: "Frank", age: 50, active: false)
      restored = key_value_only_class.from_yaml(original.to_yaml)

      expect(restored.name).to eq(original.name)
      expect(restored.age).to eq(original.age)
      expect(restored.active).to eq(original.active)
    end

    it "serializes to TOML" do
      instance = key_value_only_class.new(name: "Grace", age: 22, active: true)
      toml_str = instance.to_toml
      restored = key_value_only_class.from_toml(toml_str)

      expect(restored.name).to eq("Grace")
      expect(restored.age).to eq(22)
      expect(restored.active).to be(true)
    end
  end

  describe "XML serialization via plugin" do
    it "serializes to XML when xml block is defined" do
      instance = full_format_class.new(title: "Test Item", count: 5)
      xml = instance.to_xml

      expect(xml).to include("<item>")
      expect(xml).to include("<title>Test Item</title>")
      expect(xml).to include("<count>5</count>")
    end

    it "deserializes from XML" do
      xml = "<item><title>Parsed Item</title><count>10</count></item>"
      instance = full_format_class.from_xml(xml)

      expect(instance.title).to eq("Parsed Item")
      expect(instance.count).to eq(10)
    end

    it "round-trips through XML" do
      original = full_format_class.new(title: "Round Trip", count: 42)
      restored = full_format_class.from_xml(original.to_xml)

      expect(restored.title).to eq(original.title)
      expect(restored.count).to eq(original.count)
    end
  end

  describe "cross-format round-trips" do
    let(:instance) { full_format_class.new(title: "Cross Format", count: 99) }

    it "JSON -> XML -> JSON" do
      via_xml = full_format_class.from_xml(
        full_format_class.from_json(instance.to_json).to_xml,
      )
      restored = full_format_class.from_json(via_xml.to_json)

      expect(restored.title).to eq("Cross Format")
      expect(restored.count).to eq(99)
    end

    it "XML -> YAML -> XML" do
      via_yaml = full_format_class.from_yaml(
        full_format_class.from_xml(instance.to_xml).to_yaml,
      )
      restored = full_format_class.from_xml(via_yaml.to_xml)

      expect(restored.title).to eq("Cross Format")
      expect(restored.count).to eq(99)
    end

    it "YAML -> JSON -> XML -> TOML" do
      from_yaml = full_format_class.from_yaml(instance.to_yaml)
      from_json = full_format_class.from_json(from_yaml.to_json)
      from_xml = full_format_class.from_xml(from_json.to_xml)
      from_toml = full_format_class.from_toml(from_xml.to_toml)

      expect(from_toml.title).to eq("Cross Format")
      expect(from_toml.count).to eq(99)
    end
  end

  describe "type serializer registry" do
    it "has XML type serializers registered" do
      serializer = Lutaml::Model::Type::Value.format_type_serializer_for(
        :xml, Lutaml::Model::Type::String
      )
      expect(serializer).not_to be_nil
    end

    it "has JSON type serializers registered" do
      serializer = Lutaml::Model::Type::Value.format_type_serializer_for(
        :json, Lutaml::Model::Type::String
      )
      expect(serializer).not_to be_nil
    end

    it "has YAML type serializers registered" do
      serializer = Lutaml::Model::Type::Value.format_type_serializer_for(
        :yaml, Lutaml::Model::Type::String
      )
      expect(serializer).not_to be_nil
    end

    it "provides to_xml on type wrapper instances" do
      str = Lutaml::Model::Type::String.new("hello")
      expect(str).to respond_to(:to_xml)
      expect(str.to_xml).to eq("hello")
    end

    it "provides from_xml as a class method on types" do
      expect(Lutaml::Model::Type::String).to respond_to(:from_xml)
    end

    it "provides to_json on type wrapper instances" do
      str = Lutaml::Model::Type::String.new("hello")
      expect(str).to respond_to(:to_json)
    end

    it "provides from_json as a class method on types" do
      expect(Lutaml::Model::Type::String).to respond_to(:from_json)
    end
  end

  describe "XML-specific instance attributes via prepend" do
    it "provides element_order on model instances" do
      instance = full_format_class.new(title: "Test", count: 1)
      expect(instance).to respond_to(:element_order)
    end

    it "provides ordered? on model instances" do
      instance = full_format_class.new(title: "Test", count: 1)
      expect(instance).to respond_to(:ordered?)
    end

    it "provides mixed? on model instances" do
      instance = full_format_class.new(title: "Test", count: 1)
      expect(instance).to respond_to(:mixed?)
    end

    it "provides encoding on model instances" do
      instance = full_format_class.new(title: "Test", count: 1)
      expect(instance).to respond_to(:encoding)
    end

    it "provides schema_location on model instances" do
      instance = full_format_class.new(title: "Test", count: 1)
      expect(instance).to respond_to(:schema_location)
    end

    it "does not expose XML internals on key-value-only models" do
      instance = key_value_only_class.new(name: "Test", age: 1, active: true)
      # These respond because XML is loaded globally, but they return nil/false
      expect(instance.ordered?).to be false
      expect(instance.mixed?).to be false
      expect(instance.element_order).to be_nil
    end
  end

  describe "XML hook methods in core" do
    it "instances have format_element_sequences hook" do
      instance = full_format_class.new(title: "Test", count: 1)
      expect(instance).to respond_to(:format_element_sequences)
    end

    it "Collection has collection_structured_format? hook" do
      expect(Lutaml::Model::Collection).to respond_to(:collection_structured_format?)
    end

    it "Collection has collection_no_root_to? hook" do
      expect(Lutaml::Model::Collection).to respond_to(:collection_no_root_to?)
    end

    it "collection_structured_format? returns true for XML" do
      expect(Lutaml::Model::Collection.collection_structured_format?(:xml)).to be true
    end

    it "collection_structured_format? returns false for JSON" do
      expect(Lutaml::Model::Collection.collection_structured_format?(:json)).to be false
    end
  end

  describe "backward compatibility" do
    it "Lutaml::Model::SchemaLocation aliases to Lutaml::Xml::SchemaLocation" do
      expect(Lutaml::Model::SchemaLocation).to eq(Lutaml::Xml::SchemaLocation)
    end

    it "Lutaml::Model::Location aliases to Lutaml::Xml::Location" do
      expect(Lutaml::Model::Location).to eq(Lutaml::Xml::Location)
    end

    it "GlobalContext provides xml_namespace_registry for backward compat" do
      expect(Lutaml::Model::GlobalContext).to respond_to(:xml_namespace_registry)
    end

    it "GlobalContext provides clear_xml_namespace_registry! for backward compat" do
      expect(Lutaml::Model::GlobalContext).to respond_to(:clear_xml_namespace_registry!)
    end
  end

  describe "schema generation placeholders" do
    context "when XML is loaded" do
      it "to_xsd does not raise the placeholder error" do
        # When XML is loaded, to_xsd should be overridden by the XML plugin.
        # It may raise a different error (e.g., no root mapping) but NOT the
        # "requires lutaml-xml" placeholder error.
        error_message = begin
          full_format_class.to_xsd
          nil
        rescue StandardError => e
          e.message
        end

        if error_message
          expect(error_message).not_to include("requires lutaml-xml")
        end
      end
    end
  end

  describe "TransformationRegistry" do
    it "has an XML transformation builder registered" do
      expect(Lutaml::Model::TransformationRegistry.builder_for(:xml)).not_to be_nil
    end
  end

  describe "format-specific type serialization" do
    it "serializes Time via type wrapper for XML" do
      time_wrapper = Lutaml::Model::Type::Time.new(Time.utc(2024, 6, 15, 10,
                                                            30, 0))
      xml_result = time_wrapper.to_xml

      expect(xml_result).to be_a(String)
      expect(xml_result).to include("2024")
    end

    it "serializes Time via type wrapper for JSON" do
      time_wrapper = Lutaml::Model::Type::Time.new(Time.utc(2024, 6, 15, 10,
                                                            30, 0))
      json_result = time_wrapper.to_json

      expect(json_result).to be_a(String)
      expect(json_result).to include("2024")
    end

    it "serializes Boolean for XML as string via type wrapper" do
      true_wrapper = Lutaml::Model::Type::Boolean.new(true)
      false_wrapper = Lutaml::Model::Type::Boolean.new(false)

      expect(true_wrapper.to_xml).to eq("true")
      expect(false_wrapper.to_xml).to eq("false")
    end
  end

  describe "model without XML block" do
    it "does not create XML mappings" do
      mappings = key_value_only_class.mappings_for(:xml)
      root = mappings&.root_element

      expect(root).to be_nil
    end

    it "still creates JSON mappings" do
      mappings = key_value_only_class.mappings_for(:json)
      expect(mappings).not_to be_nil
      expect(mappings.mappings).not_to be_empty
    end

    it "still creates YAML mappings" do
      mappings = key_value_only_class.mappings_for(:yaml)
      expect(mappings).not_to be_nil
      expect(mappings.mappings).not_to be_empty
    end
  end
end
