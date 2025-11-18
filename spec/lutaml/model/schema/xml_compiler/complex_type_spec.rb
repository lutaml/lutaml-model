require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::ComplexType do
  let(:complex_type) { described_class.new }
  let(:dummy_class) do
    Class.new do
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end
  let(:simple_content_class) do
    Class.new do
      def base_class; end
      def to_attributes(indent); end
      def to_xml_mapping(indent); end
      def required_files; end
    end
  end

  describe "#initialize" do
    it "sets default base_class and empty instances" do
      expect(complex_type.base_class).to eq(described_class::SERIALIZABLE_BASE_CLASS)
      expect(complex_type.instances).to eq([])
    end

    it "allows custom base_class" do
      ct = described_class.new(base_class: "CustomBase")
      expect(ct.base_class).to eq("CustomBase")
    end
  end

  describe "attribute accessors" do
    it "allows reading and writing id, name, mixed, simple_content" do
      complex_type.id = "id"
      complex_type.name = "Name"
      complex_type.mixed = true
      complex_type.simple_content = instance_double(simple_content_class)
      expect(complex_type.id).to eq("id")
      expect(complex_type.name).to eq("Name")
      expect(complex_type.mixed).to be true
      expect(complex_type.simple_content).to be_a(RSpec::Mocks::InstanceVerifyingDouble)
    end
  end

  describe "#<<" do
    it "adds instances to the list" do
      instance = instance_double(dummy_class)
      expect { complex_type << instance }.to change {
        complex_type.instances.size
      }.by(1)
      expect(complex_type.instances).to include(instance)
    end

    it "ignores nil instances" do
      expect { complex_type << nil }.not_to(change do
        complex_type.instances.size
      end)
    end
  end

  describe "#simple_content?" do
    it "returns false if simple_content is nil or blank" do
      expect(complex_type.simple_content?).to be false
      complex_type.simple_content = nil
      expect(complex_type.simple_content?).to be false
    end

    it "returns true if simple_content is present" do
      complex_type.simple_content = instance_double(simple_content_class)
      expect(complex_type.simple_content?).to be true
    end
  end

  describe "#to_class" do
    it "renders a class with no instances or simple_content" do
      complex_type.name = "TestClass"
      code = complex_type.to_class
      expect(code).to include("class TestClass < Lutaml::Model::Serializable")
      expect(code).to include("def self.register_class_with_id")
    end

    it "renders a class with instances" do
      instance = instance_double(dummy_class,
                                 to_attributes: "  attribute :foo, :string\n", to_xml_mapping: "  map_element 'foo', to: :foo\n", required_files: [])
      complex_type.name = "TestClass"
      complex_type << instance
      code = complex_type.to_class
      expect(code).to include("attribute :foo, :string")
      expect(code).to include("map_element 'foo', to: :foo")
    end

    it "renders a class with simple_content" do
      simple_content = instance_double(simple_content_class,
                                       base_class: "string", to_attributes: "  attribute :content, :string\n", to_xml_mapping: "  map_content to: :content\n", required_files: ["require 'simple_content'"])
      complex_type.name = "TestClass"
      complex_type.simple_content = simple_content
      code = complex_type.to_class
      expect(code).to include("attribute :content, :string")
      expect(code).to include("map_content to: :content")
      expect(code).to include("require 'simple_content'")
    end

    it "renders a class with mixed content" do
      complex_type.name = "TestClass"
      complex_type.mixed = true
      code = complex_type.to_class
      expect(code).to include(", mixed: true")
    end

    it "renders a class with namespace and prefix options" do
      complex_type.name = "TestClass"
      code = complex_type.to_class(options: { namespace: "http://example.com",
                                              prefix: "ex", indent: 2 })
      expect(code).to include("namespace \"http://example.com\"", "\"ex\"")
    end
  end

  describe "#required_files" do
    it "returns require lutaml/model for default base_class" do
      expect(complex_type.required_files).to include("require \"lutaml/model\"")
    end

    it "returns require_relative for custom base_class" do
      ct = described_class.new(base_class: "foo:BarBase")
      expect(ct.required_files).to include("require_relative \"bar_base\"")
    end

    it "includes required_files from instances and simple_content" do
      instance = instance_double(dummy_class, required_files: ["require 'foo'"])
      simple_content = instance_double(simple_content_class,
                                       required_files: ["require 'bar'"])
      complex_type << instance
      complex_type.simple_content = simple_content
      expect(complex_type.required_files).to include("require 'foo'")
      expect(complex_type.required_files).to include("require 'bar'")
    end
  end

  describe "private methods" do
    it "base_class_name returns correct value" do
      expect(complex_type.send(:base_class_name)).to eq("Lutaml::Model::Serializable")
      ct = described_class.new(base_class: "foo:BarBase")
      expect(ct.send(:base_class_name)).to eq("BarBase")
    end

    it "base_class_require returns correct require line" do
      expect(complex_type.send(:base_class_require)).to eq("require \"lutaml/model\"")
      ct = described_class.new(base_class: "foo:BarBase")
      expect(ct.send(:base_class_require)).to eq("require_relative \"bar_base\"")
    end

    it "last_of_split returns last part after colon" do
      expect(complex_type.send(:last_of_split, "foo:BarBase")).to eq("BarBase")
      expect(complex_type.send(:last_of_split, "BarBase")).to eq("BarBase")
      expect(complex_type.send(:last_of_split, nil)).to be_nil
    end
  end

  describe "edge cases" do
    it "handles no instances or simple_content" do
      complex_type.name = "TestClass"
      expect { complex_type.to_class }.not_to raise_error
    end

    it "handles unusual base_class values" do
      ct = described_class.new(base_class: nil)
      ct.name = "TestClass"
      expect { ct.to_class }.not_to raise_error
    end
  end

  describe "integration" do
    it "generates valid Ruby code for a complex type" do
      complex_type.name = "TestClass"
      code = complex_type.to_class
      expect(code).to include("class TestClass < Lutaml::Model::Serializable")
      expect(code).to include("def self.register_class_with_id")
    end
  end
end
