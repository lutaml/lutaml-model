# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml"

RSpec.describe "XmlElement performance guard specs" do
  def create_xml_attribute(name, value, namespace: nil, namespace_prefix: nil)
    Lutaml::Xml::XmlAttribute.new(name, value,
                                  namespace: namespace,
                                  namespace_prefix: namespace_prefix)
  end

  def create_element(name, attributes: {}, children: [], text: "", **opts)
    Lutaml::Xml::XmlElement.new(name, attributes, children, text, **opts)
  end

  describe "attribute index optimization" do
    let(:attrs) do
      {
        "id" => create_xml_attribute("id", "123"),
        "class" => create_xml_attribute("class", "foo"),
        "ns:lang" => create_xml_attribute("ns:lang", "en",
                                          namespace: "http://ns.example.com",
                                          namespace_prefix: "ns"),
      }
    end

    let(:element) { create_element("div", attributes: attrs, name: "div") }

    describe "#find_attribute_value" do
      it "finds attribute by name" do
        expect(element.find_attribute_value("id")).to eq("123")
      end

      it "finds attribute by namespaced name" do
        expect(element.find_attribute_value("ns:lang")).to eq("en")
      end

      it "returns nil for missing attribute" do
        expect(element.find_attribute_value("missing")).to be_nil
      end

      it "finds first match from array of names" do
        result = element.find_attribute_value(["missing1", "class", "id"])
        expect(result).to eq("foo")
      end

      it "returns nil when no name in array matches" do
        expect(element.find_attribute_value(["missing1", "missing2"])).to be_nil
      end
    end

    describe "index caching" do
      it "returns same object on repeated lookups (index is built once)" do
        r1 = element.find_attribute_value("id")
        r2 = element.find_attribute_value("id")
        expect(r1).to equal(r2)
      end

      it "builds index lazily" do
        fresh = create_element("div", attributes: attrs, name: "div")
        expect(fresh.instance_variable_get(:@attribute_index)).to be_nil
        fresh.find_attribute_value("id")
        expect(fresh.instance_variable_get(:@attribute_index)).not_to be_nil
      end
    end
  end

  describe "children index optimization" do
    let(:child1) { create_element("item", name: "item") }
    let(:child2) { create_element("item", name: "item") }
    let(:child3) { create_element("other", name: "other") }

    let(:element) do
      create_element("root", children: [child1, child2, child3], name: "root")
    end

    describe "#find_children_by_name" do
      it "finds all children with matching name" do
        result = element.find_children_by_name("item")
        expect(result).to eq([child1, child2])
      end

      it "returns empty array for missing name" do
        result = element.find_children_by_name("missing")
        expect(result).to eq([])
      end

      it "collects from multiple names via array" do
        result = element.find_children_by_name(["item", "other"])
        expect(result).to eq([child1, child2, child3])
      end
    end

    describe "#find_child_by_name" do
      it "finds first child with matching name" do
        expect(element.find_child_by_name("item")).to equal(child1)
      end

      it "returns first match from array of names" do
        expect(element.find_child_by_name(["other", "item"])).to equal(child3)
      end

      it "returns nil for missing name" do
        expect(element.find_child_by_name("missing")).to be_nil
      end
    end

    describe "index invalidation" do
      it "invalidates children index when children= is called" do
        element.find_children_by_name("item")
        expect(element.instance_variable_get(:@children_index)).not_to be_nil
        element.children = [child3]
        expect(element.instance_variable_get(:@children_index)).to be_nil
        expect(element.find_children_by_name("other")).to eq([child3])
      end
    end
  end

  describe "#[] operator" do
    it "checks attributes before children" do
      attrs = { "item" => create_xml_attribute("item", "attr_value") }
      child = create_element("item", name: "item")
      element = create_element("root", attributes: attrs, children: [child],
                                       name: "root")
      # Attribute value is a string, children returns array
      result = element["item"]
      expect(result).to eq("attr_value")
    end

    it "falls back to children when attribute not found" do
      child = create_element("item", name: "item")
      element = create_element("root", children: [child], name: "root")
      result = element["item"]
      expect(result).to eq([child])
    end
  end
end
