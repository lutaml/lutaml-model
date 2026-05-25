require "spec_helper"
require "support/xml/schema_helper"

RSpec.describe Lutaml::Model::Schema::XmlCompiler::SimpleType do
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

  describe ".setup_supported_types" do
    it "returns a hash of supported types with correct instances" do
      types = described_class.setup_supported_types
      expect(types).to be_a(Hash)
      expect(types.keys).to include("nonNegativeInteger")
      expect(types["nonNegativeInteger"])
        .to be_a(Lutaml::Model::Schema::XmlCompiler::RestrictedSimpleType)
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
end

RSpec.describe Lutaml::Model::Schema::XmlCompiler::RestrictedSimpleType do
  let(:class_name) { "TestType" }
  let(:simple_type) { described_class.new(class_name) }

  describe "#initialize" do
    it "sets class_name" do
      expect(simple_type.class_name).to eq(class_name)
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
      simple_type.base_class = "string"
      simple_type.instance = Lutaml::Model::Schema::XmlCompiler::Restriction.new
    end

    it "renders the restricted simple-type template" do
      result = simple_type.to_class
      expect(result).to include("class TestType")
      expect(result).to include("def self.cast")
      expect(result).to include("register_class_with_id")
    end

    it "respects the :indent option" do
      result = simple_type.to_class(options: { indent: 4 })
      expect(result).to include("    def self.cast")
    end
  end

  describe "#required_files" do
    it "returns nil-equivalent when instance is nil" do
      expect(simple_type.required_files).to be_empty
    end

    it "returns required files from instance and parent class when not using module namespace" do
      restriction = Lutaml::Model::Schema::XmlCompiler::Restriction.new
      allow(restriction).to receive(:required_files).and_return(["require 'foo'"])
      simple_type.instance = restriction
      allow(simple_type).to receive_messages(require_parent?: true,
                                             parent_class: "ParentClass")
      expect(simple_type.required_files).to include("require 'foo'")
      expect(simple_type.required_files).to include("require_relative \"parent_class\"")
    end
  end

  describe "#parent_class" do
    it "returns the lutaml class string for skippable XSD types" do
      simple_type.base_class = "string"
      expect(simple_type.parent_class).to eq("Lutaml::Model::Type::String")
    end

    it "returns the camel-cased base_class name for non-skippable types" do
      simple_type.base_class = "nonNegativeInteger"
      expect(simple_type.parent_class).to eq("NonNegativeInteger")
    end

    it "falls back to Type::Value when no base_class is set" do
      simple_type.base_class = nil
      expect(simple_type.parent_class).to eq("Lutaml::Model::Type::Value")
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
  end
end

RSpec.describe Lutaml::Model::Schema::XmlCompiler::UnionSimpleType do
  describe "#initialize" do
    it "sets class_name and unions" do
      union = described_class.new("UnionType", ["foo", "bar"])
      expect(union.class_name).to eq("UnionType")
      expect(union.unions).to eq(["foo", "bar"])
    end
  end

  describe "#to_class" do
    it "renders the union model template" do
      union = described_class.new("UnionType", ["foo", "bar"])
      result = union.to_class
      expect(result).to include("class UnionType < Lutaml::Model::Type::Value")
      expect(result).to include("def self.cast")
      expect(result).to include("register_class_with_id")
    end

    it "emits resolve_type entries for each member, chained with ||" do
      union = described_class.new("UnionType", ["foo:Bar", "baz:Qux"])
      code = union.to_class
      expect(code).to include("Lutaml::Model::GlobalContext.resolve_type(:bar, @register).cast(value, options)")
      expect(code).to include("Lutaml::Model::GlobalContext.resolve_type(:qux, @register).cast(value, options)")
    end

    it "emits require_relative for non-skippable union members" do
      union = described_class.new("UnionType", ["foo:Bar", "baz:string"])
      code = union.to_class
      expect(code).to include("require_relative \"bar\"")
      expect(code).not_to include("require_relative \"string\"")
    end

    it "handles unions with mixed skippable and non-skippable types" do
      union = described_class.new("UnionType", ["foo:string", "bar:CustomType"])
      code = union.to_class
      expect(code).to include("require_relative \"custom_type\"")
    end
  end

  describe "integration" do
    it "generates valid Ruby code for a union type" do
      union = described_class.new("UnionType", ["foo:Bar", "baz:Qux"])
      code = union.to_class
      expect(code).to include("class UnionType < Lutaml::Model::Type::Value")
      expect(code).to include("def self.cast")
      expect(code).to include("register_class_with_id")
    end
  end
end
