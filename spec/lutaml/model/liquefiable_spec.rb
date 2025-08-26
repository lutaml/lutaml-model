require "spec_helper"
require "liquid"
require_relative "../../fixtures/address"

class LiquefiableClass
  include Lutaml::Model::Liquefiable

  attr_accessor :name, :value

  def initialize(name, value)
    @name = name
    @value = value
  end

  def display_name
    "#{name} (#{value})"
  end
end

module LiquefiableSpec
  class Glaze < Lutaml::Model::Serializable
    attribute :color, :string
    attribute :opacity, :string
  end

  class Ceramic < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :temperature, :integer
    attribute :glaze, Glaze
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :ceramics, Ceramic, collection: true
  end
end

RSpec.describe Lutaml::Model::Liquefiable do
  before do
    stub_const("DummyModel", Class.new(LiquefiableClass))
  end

  let(:dummy) { DummyModel.new("TestName", 42) }

  describe ".register_liquid_drop_class" do
    context "when drop class does not exist" do
      it "creates a new drop class" do
        expect do
          dummy.class.register_liquid_drop_class
        end.to change {
                 dummy.class.const_defined?(:DummyModelDrop)
               }
          .from(false)
          .to(true)
      end
    end

    context "when 'liquid' is not available" do
      before { allow(Object).to receive(:const_defined?).with(:Liquid).and_return(false) }

      it "raises an error" do
        expect { dummy.class.register_liquid_drop_class }.to raise_error(
          Lutaml::Model::LiquidNotEnabledError,
          "Liquid functionality is not available by default; please install and require `liquid` gem to use this functionality",
        )
      end
    end

    context "when drop class already exists" do
      it "raises an error" do
        dummy.class.register_liquid_drop_class
        expect { dummy.class.register_liquid_drop_class }.to raise_error(RuntimeError, "DummyModelDrop Already exists!")
      end
    end
  end

  describe ".drop_class_name" do
    it "returns the correct drop class name" do
      expect(dummy.class.drop_class_name).to eq("DummyModelDrop")
    end
  end

  describe ".drop_class" do
    context "when drop class exists" do
      it "returns the drop class" do
        dummy.class.register_liquid_drop_class
        expect(dummy.class.drop_class).to eq(DummyModel::DummyModelDrop)
      end
    end

    context "when drop class does not exist" do
      it "returns nil" do
        expect(dummy.class.drop_class).to be_nil
      end
    end
  end

  describe ".register_drop_method" do
    before do
      dummy.class.register_liquid_drop_class
    end

    it "defines a method on the drop class" do
      expect do
        dummy.class.register_drop_method(:display_name)
      end.to change {
               dummy.to_liquid.respond_to?(:display_name)
             }
        .from(false)
        .to(true)
    end
  end

  describe ".to_liquid" do
    context "when liquid is not enabled" do
      before { allow(Object).to receive(:const_defined?).with(:Liquid).and_return(false) }

      it "raises an error" do
        expect { dummy.to_liquid }.to raise_error(
          Lutaml::Model::LiquidNotEnabledError,
          "Liquid functionality is not available by default; please install and require `liquid` gem to use this functionality",
        )
      end
    end

    context "when liquid is enabled" do
      before do
        dummy.class.register_liquid_drop_class
        dummy.class.register_drop_method(:display_name)
      end

      it "returns an instance of the drop class" do
        expect(dummy.to_liquid).to be_a(dummy.class.drop_class)
      end

      it "allows access to registered methods via the drop class" do
        expect(dummy.to_liquid.display_name).to eq("TestName (42)")
      end
    end
  end

  context "with serializeable classes" do
    let(:address) do
      Address.new(
        {
          country: "US",
          post_code: "12345",
          person: [Person.new, Person.new],
        },
      )
    end

    describe ".to_liquid" do
      it "returns correct drop object" do
        expect(address.to_liquid).to be_a(Address::AddressDrop)
      end

      it "returns array of drops for collection objects" do
        person_classes = address.to_liquid.person.map(&:class)
        expect(person_classes).to eq([Person::PersonDrop, Person::PersonDrop])
      end

      it "returns `US` for country" do
        expect(address.to_liquid.country).to eq("US")
      end
    end
  end

  describe "working with liquid templates" do
    let(:liquid_template_dir) do
      File.join(File.dirname(__FILE__), "../../fixtures/liquid_templates")
    end

    describe "rendering simple models with liquid templates" do
      let :yaml do
        <<~YAML
          ---
          ceramics:
          - name: Porcelain Vase
            temperature: 1200
          - name: Earthenware Pot
            temperature: 950
          - name: Stoneware Jug
            temperature: 1200
        YAML
      end
      let :template_path do
        File.join(liquid_template_dir, "_ceramics_in_one.liquid")
      end

      it "renders" do
        template = Liquid::Template.parse(File.read(template_path))
        ceramic_collection = LiquefiableSpec::CeramicCollection.from_yaml(yaml)
        output = template.render("ceramic_collection" => ceramic_collection)

        expected_output = <<~OUTPUT
          * Name: "Porcelain Vase"
          ** Temperature: 1200
          * Name: "Earthenware Pot"
          ** Temperature: 950
          * Name: "Stoneware Jug"
          ** Temperature: 1200
        OUTPUT

        expect(output.strip).to eq(expected_output.strip)
      end
    end

    describe "rendering nested models with liquid templates from file system" do
      let :yaml do
        <<~YAML
          ---
          ceramics:
          - name: Celadon Bowl
            temperature: 1200
            glaze:
              color: Jade Green
              opacity: Translucent
          - name: Earthenware Pot
            temperature: 950
            glaze:
              color: Rust Red
              opacity: Opaque
          - name: Stoneware Jug
            temperature: 1200
            glaze:
              color: Cobalt Blue
              opacity: Transparent
        YAML
      end

      it "renders" do
        template = Liquid::Template.new
        file_system = Liquid::LocalFileSystem.new(liquid_template_dir)
        template.registers[:file_system] = file_system
        template.parse(file_system.read_template_file("ceramics"))

        ceramic_collection = LiquefiableSpec::CeramicCollection.from_yaml(yaml)
        output = template.render("ceramic_collection" => ceramic_collection)
        # puts output

        expected_output = <<~OUTPUT
          * Name: "Celadon Bowl"
          ** Temperature: 1200
          ** Glaze (color): Jade Green
          ** Glaze (opacity): Translucent
          * Name: "Earthenware Pot"
          ** Temperature: 950
          ** Glaze (color): Rust Red
          ** Glaze (opacity): Opaque
          * Name: "Stoneware Jug"
          ** Temperature: 1200
          ** Glaze (color): Cobalt Blue
          ** Glaze (opacity): Transparent
        OUTPUT
        expect(output.strip).to eq(expected_output.strip)
      end
    end
  end

  describe "liquid block mapping" do
    # This test demonstrates using def methods with parameters in liquid mappings
    # The def methods can accept parameters and are mapped through the liquid block
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :path, :string
        attribute :source, :string

        liquid do
          map "custom_path", to: :custom_path_method
          map "source", to: :source
          map "formatted_content", to: :format_content
        end

        # def method with optional parameter
        def custom_path_method
          File.join("templates", path)
        end

        # def method without parameters
        def format_content
          "Formatted: #{source}"
        end
      end
    end

    let(:instance) { klass.new(path: "test.xml", source: "content") }
    let(:drop) { instance.to_liquid }

    it "maps custom keys to specified methods" do
      expect(drop.custom_path).to eq("templates/test.xml")
      expect(drop.formatted_content).to eq("Formatted: content")
    end

    it "still allows direct attribute access" do
      expect(drop.source).to eq("content")
    end

    it "works with liquid templates" do
      template = Liquid::Template.parse("{{custom_path}} - {{formatted_content}}")
      result = template.render(drop)
      expect(result).to eq("templates/test.xml - Formatted: content")
    end

    it "provides both default and custom mappings" do
      # Default attribute should still be available
      expect(drop.path).to eq("test.xml")

      # Custom mapping should override for specific keys
      expect(drop.custom_path).to eq("templates/test.xml")
    end
  end

  describe "without liquid block" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :path, :string
        attribute :source, :string
      end
    end

    let(:instance) { klass.new(path: "test.xml", source: "content") }
    let(:drop) { instance.to_liquid }

    it "uses default attribute access" do
      expect(drop.path).to eq("test.xml")
      expect(drop.source).to eq("content")
    end

    it "works with liquid templates using default attributes" do
      template = Liquid::Template.parse("{{path}} - {{source}}")
      result = template.render(drop)
      expect(result).to eq("test.xml - content")
    end
  end

  describe "liquid mappings class method" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string

        liquid do
          map "display_name", to: :formatted_name
        end

        def formatted_name
          "Name: #{name}"
        end
      end
    end

    it "returns liquid mappings" do
      mappings = klass.liquid_mappings
      expect(mappings).to be_a(Lutaml::Model::Liquid::Mapping)
      expect(mappings.mappings).to eq({ "display_name" => :formatted_name })
    end

    it "returns nil when no liquid block is defined" do
      simple_klass = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end

      expect(simple_klass.liquid_mappings).to be_nil
    end
  end

  describe "custom liquid drop inheritance" do
    # Create a base model element
    let(:model_element_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "ModelElement"
        end
      end
    end

    # Create a schema class that inherits from model element
    let(:schema_class) do
      Class.new(model_element_class) do
        def self.name
          "Schema"
        end

        attribute :path, :string
        attribute :source, :string

        liquid_class "SpecialSchemaDrop" # Set the custom drop class for to_liquid
      end
    end

    let(:schema_instance) { schema_class.new(path: "test.xml", source: "content") }

    it "provides to_liquid_class method to get auto-generated drop class" do
      base_drop_class = schema_class.to_liquid_class
      expect(base_drop_class).to be_a(Class)
      expect(base_drop_class.ancestors).to include(Liquid::Drop)
    end

    it "supports method delegation to original model" do
      drop = schema_class.to_liquid_class.new(schema_instance)
      expect(drop.path).to eq("test.xml")
      expect(drop.source).to eq("content")
    end

    context "with custom drop class inheritance" do
      before do
        # Create the custom drop class that inherits from the auto-generated one
        stub_const("SpecialSchemaDrop", Class.new(schema_class.to_liquid_class) do
          # New method not in original drop
          def formatted_source
            "Formatted: #{@object.source}"
          end

          # Overriding original method
          def path
            File.join("templates", @object.path)
          end
        end)
      end

      let(:custom_drop) { SpecialSchemaDrop.new(schema_instance) }

      it "uses custom drop class when specified" do
        expect(schema_class.drop_class.name).to eq("SpecialSchemaDrop")
        expect(schema_instance.to_liquid).to be_a(schema_class.drop_class)
      end

      it "supports new methods in custom drop class" do
        expect(custom_drop.formatted_source).to eq("Formatted: content")
      end

      it "allows overriding original methods" do
        expect(custom_drop.path).to eq("templates/test.xml")
      end

      it "works with liquid templates" do
        template = Liquid::Template.parse("{{path}} - {{formatted_source}}")
        result = template.render(custom_drop)
        expect(result).to eq("templates/test.xml - Formatted: content")
      end
    end
  end
end
