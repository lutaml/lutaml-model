# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::XmlDataModel do
  describe Lutaml::Model::XmlDataModel::XmlElement do
    let(:element_name) { "test-element" }
    let(:namespace_class) do
      Class.new do
        def self.prefix_default
          "test"
        end

        def self.uri
          "http://example.com/test"
        end
      end
    end

    describe "#initialize" do
      it "creates a new XML element with name" do
        element = described_class.new(element_name)

        expect(element.name).to eq(element_name)
        expect(element.namespace_class).to be_nil
        expect(element.attributes).to eq([])
        expect(element.children).to eq([])
        expect(element.text_content).to be_nil
      end

      it "creates a new XML element with namespace" do
        element = described_class.new(element_name, namespace_class)

        expect(element.name).to eq(element_name)
        expect(element.namespace_class).to eq(namespace_class)
      end
    end

    describe "#add_child" do
      it "adds a child element" do
        parent = described_class.new("parent")
        child = described_class.new("child")

        result = parent.add_child(child)

        expect(parent.children).to eq([child])
        expect(result).to eq(parent) # returns self for chaining
      end

      it "adds text node" do
        element = described_class.new("element")

        result = element.add_child("text content")

        expect(element.children).to eq(["text content"])
        expect(result).to eq(element)
      end

      it "supports chaining" do
        parent = described_class.new("parent")
        child1 = described_class.new("child1")
        child2 = described_class.new("child2")

        parent.add_child(child1).add_child(child2)

        expect(parent.children).to eq([child1, child2])
      end
    end

    describe "#add_attribute" do
      it "adds an attribute" do
        element = described_class.new("element")
        attribute = Lutaml::Model::XmlDataModel::XmlAttribute.new(
          "attr",
          "value"
        )

        result = element.add_attribute(attribute)

        expect(element.attributes).to eq([attribute])
        expect(result).to eq(element) # returns self for chaining
      end

      it "supports chaining" do
        element = described_class.new("element")
        attr1 = Lutaml::Model::XmlDataModel::XmlAttribute.new("a1", "v1")
        attr2 = Lutaml::Model::XmlDataModel::XmlAttribute.new("a2", "v2")

        element.add_attribute(attr1).add_attribute(attr2)

        expect(element.attributes).to eq([attr1, attr2])
      end
    end

    describe "#has_children?" do
      it "returns false for element without children" do
        element = described_class.new("element")

        expect(element.has_children?).to be false
      end

      it "returns true for element with children" do
        element = described_class.new("element")
        element.add_child(described_class.new("child"))

        expect(element.has_children?).to be true
      end
    end

    describe "#has_attributes?" do
      it "returns false for element without attributes" do
        element = described_class.new("element")

        expect(element.has_attributes?).to be false
      end

      it "returns true for element with attributes" do
        element = described_class.new("element")
        attribute = Lutaml::Model::XmlDataModel::XmlAttribute.new(
          "attr",
          "value"
        )
        element.add_attribute(attribute)

        expect(element.has_attributes?).to be true
      end
    end

    describe "#qualified_name" do
      it "returns name without namespace" do
        element = described_class.new("element")

        expect(element.qualified_name).to eq("element")
      end

      it "returns prefixed name with namespace" do
        element = described_class.new("element", namespace_class)

        expect(element.qualified_name).to eq("test:element")
      end

      it "uses custom prefix override" do
        element = described_class.new("element", namespace_class)

        expect(element.qualified_name("custom")).to eq("custom:element")
      end

      it "returns unprefixed when namespace has no prefix" do
        ns_no_prefix = Class.new do
          def self.prefix_default
            nil
          end
        end
        element = described_class.new("element", ns_no_prefix)

        expect(element.qualified_name).to eq("element")
      end
    end

    describe "#to_s" do
      it "shows element name" do
        element = described_class.new("element")

        expect(element.to_s).to include("<element>")
      end

      it "shows namespace" do
        element = described_class.new("element", namespace_class)

        expect(element.to_s).to include("ns:")
      end

      it "shows attribute count" do
        element = described_class.new("element")
        element.add_attribute(
          Lutaml::Model::XmlDataModel::XmlAttribute.new("a", "v")
        )

        expect(element.to_s).to include("attrs: 1")
      end

      it "shows text content" do
        element = described_class.new("element")
        element.text_content = "text"

        expect(element.to_s).to include('text: "text"')
      end

      it "shows children count" do
        element = described_class.new("element")
        element.add_child(described_class.new("child"))

        expect(element.to_s).to include("children: 1")
      end
    end

    describe "#inspect" do
      it "includes class name and string representation" do
        element = described_class.new("element")

        expect(element.inspect).to include("XmlElement")
        expect(element.inspect).to include("<element>")
      end
    end
  end

  describe Lutaml::Model::XmlDataModel::XmlAttribute do
    let(:attr_name) { "test-attr" }
    let(:attr_value) { "test-value" }
    let(:namespace_class) do
      Class.new do
        def self.prefix_default
          "test"
        end

        def self.uri
          "http://example.com/test"
        end
      end
    end

    describe "#initialize" do
      it "creates a new XML attribute with name and value" do
        attribute = described_class.new(attr_name, attr_value)

        expect(attribute.name).to eq(attr_name)
        expect(attribute.value).to eq(attr_value)
        expect(attribute.namespace_class).to be_nil
      end

      it "creates a new XML attribute with namespace" do
        attribute = described_class.new(attr_name, attr_value, namespace_class)

        expect(attribute.name).to eq(attr_name)
        expect(attribute.value).to eq(attr_value)
        expect(attribute.namespace_class).to eq(namespace_class)
      end
    end

    describe "#qualified_name" do
      it "returns name without namespace" do
        attribute = described_class.new(attr_name, attr_value)

        expect(attribute.qualified_name).to eq(attr_name)
      end

      it "returns prefixed name with namespace" do
        attribute = described_class.new(attr_name, attr_value, namespace_class)

        expect(attribute.qualified_name).to eq("test:#{attr_name}")
      end

      it "uses custom prefix override" do
        attribute = described_class.new(attr_name, attr_value, namespace_class)

        expect(attribute.qualified_name("custom")).to eq("custom:#{attr_name}")
      end

      it "returns unprefixed when namespace has no prefix" do
        ns_no_prefix = Class.new do
          def self.prefix_default
            nil
          end
        end
        attribute = described_class.new(attr_name, attr_value, ns_no_prefix)

        expect(attribute.qualified_name).to eq(attr_name)
      end
    end

    describe "#to_s" do
      it "shows name and value" do
        attribute = described_class.new(attr_name, attr_value)

        expect(attribute.to_s).to eq('test-attr="test-value"')
      end

      it "shows prefixed name with namespace" do
        attribute = described_class.new(attr_name, attr_value, namespace_class)

        expect(attribute.to_s).to eq('test:test-attr="test-value"')
      end
    end

    describe "#inspect" do
      it "includes class name and string representation" do
        attribute = described_class.new(attr_name, attr_value)

        expect(attribute.inspect).to include("XmlAttribute")
        expect(attribute.inspect).to include('test-attr="test-value"')
      end

      it "includes namespace info when present" do
        attribute = described_class.new(attr_name, attr_value, namespace_class)

        expect(attribute.inspect).to include("ns:")
      end
    end
  end
end