require "spec_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::SimpleType do
  let(:class_name) { "TestType" }
  let(:base_class) { "string" }
  let(:unions) { [] }
  let(:simple_type) { described_class.new(class_name, unions) }

  describe "#initialize" do
    it "sets class_name and unions" do
      expect(simple_type.class_name).to eq(class_name)
      expect(simple_type.unions).to eq([])
    end

    it "allows unions to be set" do
      st = described_class.new("UnionType", ["foo", "bar"])
      expect(st.unions).to eq(["foo", "bar"])
    end
  end

  describe "attribute accessors" do
    it "allows reading and writing base_class and instance" do
      simple_type.base_class = "integer"
      expect(simple_type.base_class).to eq("integer")
      simple_type.instance = :foo
      expect(simple_type.instance).to eq(:foo)
    end
  end

  describe "#to_class" do
    before do
      simple_type.base_class = base_class
      simple_type.instance = Lutaml::Model::Schema::XmlCompiler::Restriction.new
    end

    it "renders the instance model template when no unions" do
      result = simple_type.to_class
      expect(result).to include("class TestType")
      expect(result).to include("def self.cast")
      expect(result).to include("register_class_with_id")
    end

    it "renders the union model template when unions are present" do
      st = described_class.new("UnionType", ["foo", "bar"])
      st.base_class = base_class
      st.instance = Lutaml::Model::Schema::XmlCompiler::Restriction.new
      result = st.to_class
      expect(result).to include("class UnionType < Lutaml::Model::Type::Value")
      expect(result).to include("def self.cast")
      expect(result).to include("register_class_with_id")
    end

    it "respects the :indent option" do
      result = simple_type.to_class(options: { indent: 4 })
      expect(result).to include("    def self.cast") # 4 spaces
    end
  end

  describe "#required_files" do
    it "returns nil if instance is nil" do
      expect(simple_type.required_files).to be_empty
    end

    it "returns required files from instance and parent if needed" do
      restriction = Lutaml::Model::Schema::XmlCompiler::Restriction.new
      allow(restriction).to receive(:required_files).and_return(["require 'foo'"])
      simple_type.instance = restriction
      allow(simple_type).to receive_messages(require_parent?: true,
                                             parent_class: "ParentClass")
      expect(simple_type.required_files).to include("require 'foo'")
      expect(simple_type.required_files).to include("require_relative \"parent_class\"")
    end
  end

  describe "private methods" do
    it "klass_name returns camel case" do
      expect(simple_type.send(:klass_name)).to eq("TestType")
    end

    it "parent_class returns correct class for skippable and non-skippable" do
      simple_type.base_class = "string"
      expect(simple_type.send(:parent_class)).to eq("Lutaml::Model::Type::String")
      simple_type.base_class = "nonNegativeInteger"
      expect(simple_type.send(:parent_class)).to eq("NonNegativeInteger")
      simple_type.base_class = nil
      expect(simple_type.send(:parent_class)).to eq("Lutaml::Model::Type::Value")
    end

    it "require_parent? returns correct boolean" do
      simple_type.base_class = "string"
      expect(simple_type.send(:require_parent?)).to be false
      simple_type.base_class = "unknownType"
      expect(simple_type.send(:require_parent?)).to be true
    end

    it "union_class_method_body returns correct code" do
      st = described_class.new("UnionType", ["foo:Bar", "baz:Qux"])
      expect(st.send(:union_class_method_body)).to include("register.get_class(:bar).cast(value, options)")
      expect(st.send(:union_class_method_body)).to include("register.get_class(:qux).cast(value, options)")
    end

    it "union_required_files returns correct require lines" do
      st = described_class.new("UnionType", ["foo:Bar", "baz:string"])
      expect(st.send(:union_required_files)).to include("require_relative \"bar\"")
      expect(st.send(:union_required_files)).not_to include("string")
    end
  end

  describe ".setup_supported_types" do
    it "returns a hash of supported types with correct instances" do
      types = described_class.setup_supported_types
      expect(types).to be_a(Hash)
      expect(types.keys).to include("nonNegativeInteger")
      expect(types["nonNegativeInteger"]).to be_a(described_class)
      expect(types["nonNegativeInteger"].base_class).to eq("string")
    end
  end

  describe ".setup_restriction" do
    it "returns nil if validations is nil" do
      expect(described_class.setup_restriction("string", nil)).to be_nil
    end

    it "returns a Restriction with correct values" do
      validations = { min_inclusive: 1, max_inclusive: 10, pattern: /foo/,
                      transform: "bar" }
      restriction = described_class.setup_restriction("string", validations)
      expect(restriction).to be_a(Lutaml::Model::Schema::XmlCompiler::Restriction)
      expect(restriction.base_class).to eq("string")
      expect(restriction.min_inclusive).to eq(1)
      expect(restriction.max_inclusive).to eq(10)
      expect(restriction.pattern).to eq(/foo/)
      expect(restriction.transform).to eq("bar")
    end
  end

  describe ".skippable?" do
    it "returns true for skippable types" do
      expect(described_class.skippable?("string")).to be true
      expect(described_class.skippable?("int")).to be true
    end

    it "returns false for non-skippable types" do
      expect(described_class.skippable?("nonNegativeInteger")).to be false
      expect(described_class.skippable?("id")).to be false
    end
  end

  describe "edge cases" do
    it "handles unknown base_class gracefully" do
      simple_type.base_class = nil
      expect { simple_type.send(:parent_class) }.not_to raise_error
      expect(simple_type.send(:parent_class)).to eq("Lutaml::Model::Type::Value")
    end

    it "handles unions with skippable and non-skippable types" do
      st = described_class.new("UnionType", ["foo:string", "bar:CustomType"])
      expect(st.send(:union_required_files)).to include("require_relative \"custom_type\"")
      expect(st.send(:union_required_files)).not_to include("string")
    end
  end

  describe "integration" do
    it "generates valid Ruby code for a simple type" do
      simple_type.base_class = "string"
      simple_type.instance = Lutaml::Model::Schema::XmlCompiler::Restriction.new
      code = simple_type.to_class
      expect(code).to include("class TestType")
      expect(code).to include("def self.cast")
      expect(code).to include("register_class_with_id")
    end

    it "generates valid Ruby code for a union type" do
      st = described_class.new("UnionType", ["foo:Bar", "baz:Qux"])
      st.base_class = "string"
      st.instance = Lutaml::Model::Schema::XmlCompiler::Restriction.new
      code = st.to_class
      expect(code).to include("class UnionType < Lutaml::Model::Type::Value")
      expect(code).to include("def self.cast")
      expect(code).to include("register_class_with_id")
    end
  end
end
