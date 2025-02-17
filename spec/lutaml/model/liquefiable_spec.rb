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
end
