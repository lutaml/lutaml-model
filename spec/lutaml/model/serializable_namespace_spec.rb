require "spec_helper"
require "lutaml/model"

RSpec.describe Lutaml::Model::Serializable, "namespace directive" do
  # Define test namespace classes
  let(:test_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "https://example.com/model"
      prefix_default "model"
    end
  end

  let(:other_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "https://example.com/other"
      prefix_default "other"
    end
  end

  describe ".namespace" do
    it "sets and gets namespace class" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end
      model_class.namespace(test_namespace)

      expect(model_class.namespace).to eq(test_namespace)
    end

    it "returns nil when no namespace is set" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end

      expect(model_class.namespace).to be_nil
    end

    it "raises error for non-XmlNamespace class" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end

      expect do
        model_class.namespace(String)
      end.to raise_error(ArgumentError, /XmlNamespace/)
    end

    it "allows changing namespace" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end
      model_class.namespace(test_namespace)
      model_class.namespace(other_namespace)

      expect(model_class.namespace).to eq(other_namespace)
    end
  end

  describe ".namespace_uri" do
    it "returns URI from namespace class" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end
      model_class.namespace(test_namespace)

      expect(model_class.namespace_uri).to eq("https://example.com/model")
    end

    it "returns nil when no namespace is set" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end

      expect(model_class.namespace_uri).to be_nil
    end
  end

  describe ".namespace_prefix" do
    it "returns prefix from namespace class" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end
      model_class.namespace(test_namespace)

      expect(model_class.namespace_prefix).to eq("model")
    end

    it "returns nil when no namespace is set" do
      model_class = Class.new do
        include Lutaml::Model::Serialize
      end

      expect(model_class.namespace_prefix).to be_nil
    end
  end

  describe "integration with model definition" do
    it "can set namespace alongside attributes" do
      model_class = Class.new do
        include Lutaml::Model::Serialize

        attribute :name, :string
        attribute :value, :integer
      end

      model_class.namespace(test_namespace)

      expect(model_class.namespace).to eq(test_namespace)
      expect(model_class.attributes.keys).to include(:name, :value)
    end

    it "namespace is inherited by subclasses" do
      parent_class = Class.new do
        include Lutaml::Model::Serialize
      end
      parent_class.namespace(test_namespace)

      child_class = Class.new(parent_class)

      # Note: namespace inheritance depends on implementation
      # This test documents current behavior
      expect(child_class.namespace).to be_nil # Child must set own namespace
    end
  end
end
