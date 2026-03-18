# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::TransformationBuilder do
  describe ".build" do
    it "raises NotImplementedError" do
      expect do
        described_class.build(nil, nil, nil, nil)
      end.to raise_error(NotImplementedError, /must be implemented/)
    end
  end

  describe ".handles?" do
    context "when FORMATS constant is defined" do
      it "returns true for formats in FORMATS" do
        # Use XmlTransformationBuilder which has FORMATS defined
        expect(Lutaml::Xml::TransformationBuilder.handles?(:xml)).to be true
      end

      it "returns false for formats not in FORMATS" do
        expect(Lutaml::Xml::TransformationBuilder.handles?(:json)).to be false
        expect(Lutaml::Xml::TransformationBuilder.handles?(:protobuf)).to be false
      end
    end

    context "when FORMATS constant is not defined" do
      it "returns false for all formats" do
        # Create a fresh builder class without FORMATS
        builder_class = Class.new(described_class)
        expect(builder_class.handles?(:xml)).to be false
        expect(builder_class.handles?(:json)).to be false
      end
    end
  end
end

RSpec.describe Lutaml::Xml::TransformationBuilder do
  describe "FORMATS" do
    it "includes :xml" do
      expect(described_class::FORMATS).to include(:xml)
    end

    it "is frozen" do
      expect(described_class::FORMATS).to be_frozen
    end
  end

  describe ".handles?" do
    it "returns true for :xml" do
      expect(described_class.handles?(:xml)).to be true
    end

    it "returns false for other formats" do
      expect(described_class.handles?(:json)).to be false
      expect(described_class.handles?(:yaml)).to be false
    end
  end

  describe ".build" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          root "person"
          map_element "name", to: :name
        end
      end
    end

    it "creates an Xml::Transformation instance" do
      mapping = model_class.mappings[:xml]
      result = described_class.build(model_class, mapping, :xml, nil)

      expect(result).to be_a(Lutaml::Xml::Transformation)
    end

    it "passes correct parameters to transformation" do
      mapping = model_class.mappings[:xml]
      result = described_class.build(model_class, mapping, :xml, nil)

      expect(result.model_class).to eq(model_class)
      expect(result.format).to eq(:xml)
    end
  end
end

RSpec.describe Lutaml::KeyValue::TransformationBuilder do
  describe "FORMATS" do
    it "includes :json, :yaml, :toml, :hash" do
      expect(described_class::FORMATS).to contain_exactly(:json, :yaml, :toml,
                                                          :hash)
    end

    it "is frozen" do
      expect(described_class::FORMATS).to be_frozen
    end
  end

  describe ".handles?" do
    it "returns true for key-value formats" do
      expect(described_class.handles?(:json)).to be true
      expect(described_class.handles?(:yaml)).to be true
      expect(described_class.handles?(:toml)).to be true
      expect(described_class.handles?(:hash)).to be true
    end

    it "returns false for other formats" do
      expect(described_class.handles?(:xml)).to be false
      expect(described_class.handles?(:protobuf)).to be false
    end
  end

  describe ".build" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        json do
          map "name", to: :name
        end
      end
    end

    it "creates a KeyValue::Transformation instance" do
      mapping = model_class.mappings[:json]
      result = described_class.build(model_class, mapping, :json, nil)

      expect(result).to be_a(Lutaml::KeyValue::Transformation)
    end

    it "works with different key-value formats" do
      %i[json yaml toml hash].each do |format|
        mapping = model_class.mappings[format] || model_class.send(
          :default_mappings, format
        )
        result = described_class.build(model_class, mapping, format, nil)

        expect(result).to be_a(Lutaml::KeyValue::Transformation)
        expect(result.format).to eq(format)
      end
    end
  end
end

RSpec.describe "TransformationRegistry Builder Pattern" do
  before do
    Lutaml::Model::TransformationRegistry.reset_builders!
    Lutaml::Model::TransformationRegistry.instance.clear
  end

  describe ".register_builder" do
    context "when builder inherits from TransformationBuilder" do
      it "registers the builder for the format" do
        custom_builder = Class.new(Lutaml::Model::TransformationBuilder) do
          def self.build(_model_class, _mapping, _format, _register)
            "custom_transformation"
          end
        end

        Lutaml::Model::TransformationRegistry.register_builder(:custom,
                                                               custom_builder)

        expect(Lutaml::Model::TransformationRegistry.builder_for(:custom)).to eq(custom_builder)
      end
    end

    context "when builder does not inherit from TransformationBuilder" do
      it "raises ArgumentError" do
        invalid_builder = Class.new

        expect do
          Lutaml::Model::TransformationRegistry.register_builder(:invalid,
                                                                 invalid_builder)
        end.to raise_error(ArgumentError,
                           /must inherit from TransformationBuilder/)
      end
    end
  end

  describe ".builder_for" do
    it "returns XmlTransformationBuilder for :xml" do
      expect(Lutaml::Model::TransformationRegistry.builder_for(:xml)).to eq(Lutaml::Xml::TransformationBuilder)
    end

    it "returns KeyValueTransformationBuilder for :json" do
      expect(Lutaml::Model::TransformationRegistry.builder_for(:json)).to eq(Lutaml::KeyValue::TransformationBuilder)
    end

    it "returns KeyValueTransformationBuilder for :yaml" do
      expect(Lutaml::Model::TransformationRegistry.builder_for(:yaml)).to eq(Lutaml::KeyValue::TransformationBuilder)
    end

    it "returns nil for unregistered format" do
      expect(Lutaml::Model::TransformationRegistry.builder_for(:unknown_format)).to be_nil
    end
  end

  describe ".reset_builders!" do
    it "resets to default builders" do
      # Register a custom builder
      custom_builder = Class.new(Lutaml::Model::TransformationBuilder) do
        def self.build(*)
          "custom"
        end
      end
      Lutaml::Model::TransformationRegistry.register_builder(:xml,
                                                             custom_builder)

      # Reset
      Lutaml::Model::TransformationRegistry.reset_builders!

      # Should have default builders again
      expect(Lutaml::Model::TransformationRegistry.builder_for(:xml)).to eq(Lutaml::Xml::TransformationBuilder)
    end
  end

  describe "#build_transformation" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        xml do
          root "person"
          map_element "name", to: :name
        end

        json do
          map "name", to: :name
        end
      end
    end

    it "uses registered builder for XML format" do
      mapping = model_class.mappings[:xml]
      registry = Lutaml::Model::TransformationRegistry.instance

      result = registry.send(:build_transformation, model_class, mapping, :xml,
                             nil)
      expect(result).to be_a(Lutaml::Xml::Transformation)
    end

    it "uses registered builder for JSON format" do
      mapping = model_class.mappings[:json]
      registry = Lutaml::Model::TransformationRegistry.instance

      result = registry.send(:build_transformation, model_class, mapping,
                             :json, nil)
      expect(result).to be_a(Lutaml::KeyValue::Transformation)
    end

    it "returns mapping directly for unregistered format" do
      mapping = double("mapping")
      registry = Lutaml::Model::TransformationRegistry.instance

      result = registry.send(:build_transformation, model_class, mapping,
                             :unknown_format, nil)
      expect(result).to eq(mapping)
    end
  end

  describe "Open/Closed Principle" do
    it "allows adding new formats without modifying TransformationRegistry" do
      # Create a custom builder
      custom_builder = Class.new(Lutaml::Model::TransformationBuilder) do
        def self.build(_model_class, _mapping, format, _register)
          "custom_transformation_for_#{format}"
        end
      end

      # Register the builder
      Lutaml::Model::TransformationRegistry.register_builder(:custom,
                                                             custom_builder)

      # Use it
      registry = Lutaml::Model::TransformationRegistry.instance
      result = registry.send(:build_transformation, nil, nil, :custom, nil)

      expect(result).to eq("custom_transformation_for_custom")
    end
  end
end
