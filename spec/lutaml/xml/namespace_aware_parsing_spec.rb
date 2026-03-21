# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace-Aware XML Parsing" do
  # Define test namespace classes
  let(:ns_v1) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/ns/v1"
      prefix_default "v1"
    end
  end

  let(:ns_v2) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/ns/v2"
      prefix_default "v2"
    end
  end

  let(:ns_common) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/ns/common"
      prefix_default "common"
    end
  end

  # Define version-specific model classes
  let(:v1_model_class) do
    ns = ns_v1
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :version, :string

      xml do
        namespace ns
        root "Model"
        map_element "Name", to: :name
        map_element "Version", to: :version
      end
    end
  end

  let(:v2_model_class) do
    ns = ns_v2
    Class.new(Lutaml::Model::Serializable) do
      attribute :title, :string
      attribute :version, :string

      xml do
        namespace ns
        root "Model"
        map_element "Title", to: :title
        map_element "Version", to: :version
      end
    end
  end

  let(:common_class) do
    ns = ns_common
    Class.new(Lutaml::Model::Serializable) do
      attribute :id, :string

      xml do
        namespace ns
        root "Common"
        map_element "Id", to: :id
      end
    end
  end

  before do
    Lutaml::Model::GlobalContext.reset!

    # Create registers with fallback chain
    @common_register = Lutaml::Model::Register.new(:common)
    @v1_register = Lutaml::Model::Register.new(:v1, fallback: [:common])
    @v2_register = Lutaml::Model::Register.new(:v2, fallback: [:v1, :common])

    # Register in GlobalRegister
    Lutaml::Model::GlobalRegister.register(@common_register)
    Lutaml::Model::GlobalRegister.register(@v1_register)
    Lutaml::Model::GlobalRegister.register(@v2_register)

    # Bind namespaces
    @common_register.bind_namespace(ns_common)
    @v1_register.bind_namespace(ns_v1)
    @v2_register.bind_namespace(ns_v2)

    # Register models
    @common_register.register_model(common_class, id: :common)
    @v1_register.register_model(v1_model_class, id: :model)
    @v2_register.register_model(v2_model_class, id: :model)
  end

  after do
    Lutaml::Model::GlobalContext.reset!
  end

  describe "Attribute#type_with_namespace" do
    it "returns standard type when no namespace provided" do
      attr = v1_model_class.attributes[:name]
      expect(attr.type_with_namespace(@v1_register)).to eq(Lutaml::Model::Type::String)
    end

    it "returns standard type when namespace not bound" do
      attr = v1_model_class.attributes[:name]
      expect(attr.type_with_namespace(@v1_register, "http://unknown.com")).to eq(Lutaml::Model::Type::String)
    end

    it "handles Symbol register parameter" do
      attr = v1_model_class.attributes[:name]
      expect(attr.type_with_namespace(:v1, "http://example.com/ns/v1")).to eq(Lutaml::Model::Type::String)
    end

    it "handles nil register parameter" do
      attr = v1_model_class.attributes[:name]
      expect(attr.type_with_namespace(nil, "http://example.com/ns/v1")).to eq(Lutaml::Model::Type::String)
    end
  end

  describe "Register#resolve_in_namespace" do
    it "finds type in own register" do
      result = @v1_register.resolve_in_namespace(:model, ns_v1.uri)
      expect(result).to eq(v1_model_class)
    end

    it "finds type via fallback chain" do
      result = @v2_register.resolve_in_namespace(:model, ns_v1.uri)
      expect(result).to eq(v1_model_class)
    end

    it "finds common type via deep fallback" do
      result = @v2_register.resolve_in_namespace(:common, ns_common.uri)
      expect(result).to eq(common_class)
    end

    it "returns nil for unknown type" do
      result = @v1_register.resolve_in_namespace(:unknown_type, ns_v1.uri)
      expect(result).to be_nil
    end

    it "returns nil when namespace not handled" do
      result = @v1_register.resolve_in_namespace(:model, "http://unknown.com")
      expect(result).to be_nil
    end
  end

  describe "GlobalContext#register_for_namespace" do
    it "returns register bound to namespace" do
      result = Lutaml::Model::GlobalContext.register_for_namespace(ns_v1.uri)
      expect(result).to eq(@v1_register)
    end

    it "returns nil for unbound namespace" do
      result = Lutaml::Model::GlobalContext.register_for_namespace("http://unknown.com")
      expect(result).to be_nil
    end
  end

  describe "End-to-end namespace-aware parsing" do
    it "parses V1 XML with V1 model" do
      xml = <<~XML
        <v1:Model xmlns:v1="http://example.com/ns/v1">
          <v1:Name>Test Model</v1:Name>
          <v1:Version>1.0</v1:Version>
        </v1:Model>
      XML

      model = v1_model_class.from_xml(xml)
      expect(model.name).to eq("Test Model")
      expect(model.version).to eq("1.0")
    end

    it "parses V2 XML with V2 model" do
      xml = <<~XML
        <v2:Model xmlns:v2="http://example.com/ns/v2">
          <v2:Title>Enhanced Model</v2:Title>
          <v2:Version>2.0</v2:Version>
        </v2:Model>
      XML

      model = v2_model_class.from_xml(xml)
      expect(model.title).to eq("Enhanced Model")
      expect(model.version).to eq("2.0")
    end

    it "round-trips XML preserving namespaces" do
      xml = <<~XML
        <v1:Model xmlns:v1="http://example.com/ns/v1">
          <v1:Name>Test</v1:Name>
          <v1:Version>1.0</v1:Version>
        </v1:Model>
      XML

      model = v1_model_class.from_xml(xml)
      output = model.to_xml

      # Re-parse and verify content
      reparsed = v1_model_class.from_xml(output)
      expect(reparsed.name).to eq("Test")
      expect(reparsed.version).to eq("1.0")
    end

    it "parses with default namespace" do
      xml = <<~XML
        <Model xmlns="http://example.com/ns/v1">
          <Name>Test</Name>
          <Version>1.0</Version>
        </Model>
      XML

      model = v1_model_class.from_xml(xml)
      expect(model.name).to eq("Test")
      expect(model.version).to eq("1.0")
    end
  end
end
