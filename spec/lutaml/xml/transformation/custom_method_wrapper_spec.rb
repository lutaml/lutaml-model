# frozen_string_literal: true

require "spec_helper"
require "lutaml/xml"

RSpec.describe Lutaml::Xml::CustomMethodWrapper do
  let(:parent) { Lutaml::Xml::DataModel::XmlElement.new("parent") }
  let(:wrapper) { described_class.new(parent) }

  describe "#create_element" do
    it "returns a new XmlElement with the given name" do
      el = wrapper.create_element("foo")
      expect(el).to be_a(Lutaml::Xml::DataModel::XmlElement)
      expect(el.name).to eq("foo")
    end

    it "does not add the element to any parent" do
      wrapper.create_element("orphan")
      expect(parent.children).to be_empty
    end
  end

  describe "#add_element" do
    it "adds an XmlElement child with single-argument form" do
      child = Lutaml::Xml::DataModel::XmlElement.new("child")
      result = wrapper.add_element(child)
      expect(result).to eq(child)
      expect(parent.children).to eq([child])
    end

    it "adds an XmlElement child with two-argument form" do
      child = Lutaml::Xml::DataModel::XmlElement.new("child")
      wrapper.add_element(parent, child)
      expect(parent.children).to eq([child])
    end

    it "parses XML string fragments via Moxml" do
      wrapper.add_element(parent, "<a title=\"copyright\">one</a><b>two</b>")
      expect(parent.children.map(&:name)).to eq(%w[a b])
      expect(parent.children[0].attributes.first.value).to eq("copyright")
      expect(parent.children[0].text_content).to eq("one")
      expect(parent.children[1].text_content).to eq("two")
    end

    it "raises TypeError for unsupported types" do
      foreign = instance_double(Object)
      expect do
        wrapper.add_element(parent, foreign)
      end.to raise_error(TypeError,
                         /add_element expects a String or XmlElement/)
    end

    it "parses nested XML elements recursively" do
      wrapper.add_element(parent, "<outer><inner>text</inner></outer>")
      outer = parent.children.first
      expect(outer.name).to eq("outer")
      expect(outer.children.first.name).to eq("inner")
      expect(outer.children.first.text_content).to eq("text")
    end
  end

  describe "#add_text" do
    it "sets text_content on the given element" do
      el = Lutaml::Xml::DataModel::XmlElement.new("p")
      wrapper.add_text(el, "hello")
      expect(el.text_content).to eq("hello")
    end

    it "sets text on current context when element is nil" do
      wrapper.add_text(nil, "fallback")
      expect(parent.text_content).to eq("fallback")
    end

    it "sets text on current context when wrapper itself is passed" do
      wrapper.add_text(wrapper, "via-doc")
      expect(parent.text_content).to eq("via-doc")
    end
  end

  describe "#add_attribute" do
    it "adds an attribute to the element" do
      el = Lutaml::Xml::DataModel::XmlElement.new("node")
      wrapper.add_attribute(el, "id", "42")
      expect(el.attributes.size).to eq(1)
      expect(el.attributes.first.name).to eq("id")
      expect(el.attributes.first.value).to eq("42")
    end

    it "coerces name and value to strings" do
      el = Lutaml::Xml::DataModel::XmlElement.new("node")
      wrapper.add_attribute(el, :key, 123)
      expect(el.attributes.first.name).to eq("key")
      expect(el.attributes.first.value).to eq("123")
    end
  end

  describe "#create_and_add_element" do
    it "creates and adds element to current context" do
      el = wrapper.create_and_add_element("item")
      expect(el.name).to eq("item")
      expect(parent.children).to eq([el])
    end

    it "creates element with attributes" do
      el = wrapper.create_and_add_element("item", attributes: { id: "1" })
      expect(el.attributes.first.name).to eq("id")
      expect(el.attributes.first.value).to eq("1")
    end

    it "yields ElementWrapper in block form" do
      wrapper.create_and_add_element("outer") do |w|
        w.add_text(w, "content")
      end
      outer = parent.children.first
      expect(outer.text_content).to eq("content")
    end

    it "supports nested create_and_add_element in block" do
      wrapper.create_and_add_element("outer") do |w|
        w.create_and_add_element("inner") do |iw|
          iw.add_text(iw, "deep")
        end
      end
      outer = parent.children.first
      inner = outer.children.first
      expect(inner.name).to eq("inner")
      expect(inner.text_content).to eq("deep")
    end

    it "restores context after block exits" do
      wrapper.create_and_add_element("outer") do |_w|
        # context is now "outer"
      end
      # context should be back to parent
      el = wrapper.create_and_add_element("after")
      expect(parent.children).to include(el)
    end
  end

  describe "#push_context / #pop_context" do
    it "manages a stack of context elements" do
      child = Lutaml::Xml::DataModel::XmlElement.new("child")
      wrapper.push_context(child)
      expect(wrapper.current_context).to eq(child)
      wrapper.pop_context
      expect(wrapper.current_context).to eq(parent)
    end

    it "does not pop below the root context" do
      wrapper.pop_context
      expect(wrapper.current_context).to eq(parent)
    end
  end

  describe ".build_element" do
    it "creates an element with attributes" do
      el = described_class.build_element("tag", { a: "1", b: "2" })
      expect(el.name).to eq("tag")
      expect(el.attributes.map(&:name)).to eq(%w[a b])
    end

    it "handles nil attributes hash" do
      el = described_class.build_element("tag", nil)
      expect(el.attributes).to be_empty
    end
  end

  describe Lutaml::Xml::CustomMethodWrapper::ElementWrapper do
    let(:element) { Lutaml::Xml::DataModel::XmlElement.new("el") }
    let(:ew) { described_class.new(element) }

    describe "#add_text" do
      it "sets text and cdata flag" do
        ew.add_text(ew, "data", cdata: true)
        expect(element.text_content).to eq("data")
        expect(element.cdata).to be true
      end

      it "handles cdata as hash format" do
        ew.add_text(ew, "data", cdata: { cdata: true })
        expect(element.cdata).to be true
      end

      it "defaults cdata to false" do
        ew.add_text(ew, "data")
        expect(element.cdata).to be false
      end
    end

    describe "#create_and_add_element" do
      it "adds child to wrapped element" do
        child = ew.create_and_add_element("sub")
        expect(element.children).to eq([child])
      end

      it "yields nested wrapper in block form" do
        ew.create_and_add_element("sub") do |sub|
          sub.add_text(sub, "text")
        end
        expect(element.children.first.text_content).to eq("text")
      end
    end
  end

  describe "XmlElement#add_child type guard" do
    it "accepts XmlElement" do
      child = Lutaml::Xml::DataModel::XmlElement.new("ok")
      expect { parent.add_child(child) }.not_to raise_error
    end

    it "accepts String" do
      expect { parent.add_child("text") }.not_to raise_error
    end

    it "accepts XmlComment" do
      comment = Lutaml::Xml::DataModel::XmlComment.new("a comment")
      expect { parent.add_child(comment) }.not_to raise_error
    end

    it "rejects foreign types" do
      expect do
        parent.add_child(42)
      end.to raise_error(TypeError, /XmlElement#add_child expects/)
    end
  end

  describe "RuleApplier integration" do
    it "loads the wrapper through the public XML autoload path" do
      parent_el = Lutaml::Xml::DataModel::XmlElement.new("parent")
      model_class = Class.new do
        def custom_to_xml(_model, parent, wrapper)
          wrapper.add_text(parent, "ok")
        end
      end
      rule = Struct.new(:custom_methods).new({ to: :custom_to_xml })
      applier = Class.new do
        include Lutaml::Xml::TransformationSupport::RuleApplier

        public :apply_custom_method
      end.new

      applier.apply_custom_method(parent_el, rule, model_class, Object.new)

      expect(parent_el.text_content).to eq("ok")
    end
  end
end
