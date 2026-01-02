require "spec_helper"

class TestModel < Lutaml::Model::Serializable
  attribute :_class, :string, default: -> { self.class.name }
end

RSpec.describe Lutaml::Model::Services::DefaultValueResolver do
  let(:register) { Lutaml::Model::Config.default_register }
  let(:instance) { nil }

  describe "#default_value" do
    context "when default is a static value" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string, default: "John")
      end

      it "returns the static value" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default_value).to eq("John")
      end
    end

    context "when default is a proc without instance context" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("count", :integer, default: -> { 42 })
      end

      it "executes the proc" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default_value).to eq(42)
      end
    end

    context "when default is a proc with instance context" do
      let(:model) { TestModel.new }
      let(:attribute) { TestModel.attributes[:_class] }

      it "executes the proc in the instance context" do
        resolver = described_class.new(attribute, register, model)
        expect(resolver.default_value).to eq("TestModel")
      end
    end
  end

  describe "#default" do
    context "when default is a static value" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("count", :integer, default: "42")
      end

      it "returns the casted value" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default).to eq(42)
      end
    end

    context "when default is a proc" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("file", :string, default: -> { Pathname.new("avatar.png") })
      end

      it "returns the casted proc result" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default).to eq("avatar.png")
      end
    end

    context "when default is a proc with instance context" do
      let(:model) { TestModel.new }
      let(:attribute) { TestModel.attributes[:_class] }

      it "executes and casts the proc in the instance context" do
        resolver = described_class.new(attribute, register, model)
        expect(resolver.default).to eq("TestModel")
      end
    end
  end

  describe "#raw_default_value" do
    context "when default is not set" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string)
      end

      it "returns uninitialized" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.raw_default_value).to be(Lutaml::Model::UninitializedClass.instance)
      end
    end

    context "when default is a static value" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string, default: "John")
      end

      it "returns the static value without execution" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.raw_default_value).to eq("John")
      end
    end

    context "when default is a proc" do
      let(:proc_default) { -> { "John" } }
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string, default: proc_default)
      end

      it "returns the proc without execution" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.raw_default_value).to eq(proc_default)
      end
    end

    context "when default is nil" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("value", :string, default: nil)
      end

      it "returns nil" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.raw_default_value).to be_nil
      end
    end
  end

  describe "#default_set?" do
    context "when default is not set" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string)
      end

      it "returns false" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default_set?).to be(false)
      end
    end

    context "when default is a static value" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string, default: "John")
      end

      it "returns true" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default_set?).to be(true)
      end
    end

    context "when default is a proc" do
      let(:attribute) do
        Lutaml::Model::Attribute.new("name", :string, default: -> { "John" })
      end

      it "returns true" do
        resolver = described_class.new(attribute, register, instance)
        expect(resolver.default_set?).to be(true)
      end
    end
  end
end
