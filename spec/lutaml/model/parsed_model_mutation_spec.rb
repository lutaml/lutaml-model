require "spec_helper"
require_relative "../../../lib/lutaml/model"

# Regression coverage for the parsed-vs-built divergence: a model parsed from
# a document carries element_order, and mutations made after parsing used to
# be dropped during serialization.
#
# Every example here PARSES input, mutates, then serializes, and asserts on
# the emitted document. Asserting on attribute reads is what hid these bugs —
# the value always reads back correctly.
module ParsedModelMutationSpec
  class Child < Lutaml::Model::Serializable
    attribute :v, :string

    xml do
      root "child"
      map_attribute "v", to: :v
    end
  end

  class Mixed < Lutaml::Model::Serializable
    attribute :a, Child
    attribute :b, Child

    xml do
      root "p"
      mixed_content
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end

  class MixColl < Lutaml::Model::Serializable
    attribute :a, Child, collection: true
    attribute :b, Child

    xml do
      root "p"
      mixed_content
      map_element "a", to: :a
      map_element "b", to: :b
    end
  end

  class EmptyColl < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :blank_topic, :string, collection: true
    attribute :nil_topic, :string, collection: true
    attribute :plain_topic, :string, collection: true

    xml do
      root "s"
      ordered
      map_element "lead", to: :lead
      map_element "blank", to: :blank_topic, render_empty: :as_blank
      map_element "nil", to: :nil_topic, render_empty: :as_nil
      map_element "plain", to: :plain_topic
    end
  end

  class NilColl < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :items, :string, collection: true

    xml do
      root "s"
      ordered
      map_element "lead", to: :lead
      map_element "item", to: :items, render_nil: :as_nil
    end
  end

  class DefaultColl < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :items, :string, collection: true, default: -> { [] }

    xml do
      root "s"
      ordered
      map_element "lead", to: :lead
      map_element "item", to: :items
    end
  end

  class DerivedOrdered < Lutaml::Model::Serializable
    attribute :lead, :string
    attribute :calc, :string, method: :calc_value

    xml do
      root "s"
      ordered
      map_element "lead", to: :lead
      map_element "calc", to: :calc
    end

    def calc_value
      "D"
    end
  end

  class Aliased < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "p"
      ordered
      map_element %w[item old-item], to: :items
    end
  end

  class Glaze < Lutaml::Model::Serializable
    attribute :color, :string
  end

  class Delegating < Lutaml::Model::Serializable
    attribute :glaze, Glaze
    attribute :other, :string

    xml do
      root "d"
      ordered
      map_element "color", to: :color, delegate: :glaze
      map_element "other", to: :other
    end
  end

  class CustomColl < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "p"
      ordered
      map_element "item", to: :items, with: { to: :items_to, from: :items_from }
    end

    def items_to(model, parent, doc)
      Array(model.items).each do |v|
        el = doc.create_element("item")
        doc.add_text(el, v)
        parent.add_child(el)
      end
    end

    def items_from(model, values)
      model.items = Array(values).map(&:to_s)
    end
  end

  class Inner < Lutaml::Model::Serializable
    attribute :x, :string
  end

  class DelegatingAlias < Lutaml::Model::Serializable
    attribute :inner, Inner
    attribute :other, :string

    xml do
      root "d"
      ordered
      map_element %w[x old-x], to: :x, delegate: :inner
      map_element "other", to: :other
    end
  end

  class SameNameA < Lutaml::Model::Serializable
    attribute :v, :string

    xml do
      root "sa"
      map_attribute "v", to: :v
    end
  end

  class SameNameB < Lutaml::Model::Serializable
    attribute :w, :string

    xml do
      root "sb"
      map_attribute "w", to: :w
    end
  end

  class AmbiguousNames < Lutaml::Model::Serializable
    attribute :a, SameNameA
    attribute :b, SameNameB

    xml do
      root "p"
      ordered
      map_element "same", to: :a
      map_element "same", to: :b
    end
  end

  class CustomMethod < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      root "c"
      ordered
      map_element "label", with: { to: :label_to_xml, from: :label_from_xml }
      map_element "name", to: :name
    end

    def label_to_xml(model, parent, doc)
      el = doc.create_element("label")
      doc.add_text(el, "L:#{model.name}")
      parent.add_child(el)
    end

    def label_from_xml(model, value)
      model.name = Array(value).first.to_s.sub(/^L:/, "")
    end
  end
end

RSpec.describe "parsed model mutation" do
  # Defect 1: mixed_content dropped an attribute set after parse.
  describe "singular element set after parse" do
    it "emits the element that was set" do
      model = ParsedModelMutationSpec::Mixed.from_xml('<p><a v="1"/></p>')
      model.b = ParsedModelMutationSpec::Child.new(v: "2")

      expect(model.to_xml).to include('<b v="2"/>').or include('<b v="2"></b>')
    end

    it "emits it in mapping-declaration order" do
      model = ParsedModelMutationSpec::Mixed.from_xml('<p><b v="2"/></p>')
      model.a = ParsedModelMutationSpec::Child.new(v: "1")

      expect(model.to_xml.index("<a ")).to be < model.to_xml.index("<b ")
    end

    it "leaves an untouched round-trip unchanged" do
      xml = '<p><a v="1"/></p>'
      model = ParsedModelMutationSpec::Mixed.from_xml(xml)

      expect(model.to_xml).not_to include("<b")
    end

    it "is idempotent across repeated serialization" do
      model = ParsedModelMutationSpec::Mixed.from_xml('<p><a v="1"/></p>')
      model.b = ParsedModelMutationSpec::Child.new(v: "2")

      first = model.to_xml
      second = model.to_xml

      expect(second).to eq(first)
      expect(second.scan("<b").size).to eq(1)
    end
  end

  # Defect 2: mixed_content ignored collection growth.
  describe "collection grown after parse" do
    it "emits every item" do
      model = ParsedModelMutationSpec::MixColl.from_xml('<p><a v="1"/></p>')
      model.a = [
        ParsedModelMutationSpec::Child.new(v: "1"),
        ParsedModelMutationSpec::Child.new(v: "2"),
      ]

      expect(model.to_xml.scan("<a ").size).to eq(2)
    end

    it "still emits the right count when the collection shrinks" do
      model = ParsedModelMutationSpec::MixColl
        .from_xml('<p><a v="1"/><a v="2"/></p>')
      model.a = [ParsedModelMutationSpec::Child.new(v: "9")]

      expect(model.to_xml.scan("<a ").size).to eq(1)
    end

    it "appends new items after existing ones, not before an interleaved element" do
      model = ParsedModelMutationSpec::MixColl
        .from_xml('<p><a v="1"/><b v="B"/><a v="2"/></p>')
      model.a = [
        ParsedModelMutationSpec::Child.new(v: "1"),
        ParsedModelMutationSpec::Child.new(v: "2"),
        ParsedModelMutationSpec::Child.new(v: "3"),
      ]

      xml = model.to_xml
      expect(xml.index('v="3"')).to be > xml.index('v="2"')
    end

    it "shares one counter across canonical and alias element names" do
      model = ParsedModelMutationSpec::Aliased
        .from_xml("<p><old-item>x</old-item></p>")
      model.items = %w[x y]

      xml = model.to_xml
      expect(xml).to include("x")
      expect(xml).to include("y")
    end
  end

  # Defect 3: element_order was frozen on parsed models.
  describe "element_order on a parsed model" do
    it "is mutable" do
      model = ParsedModelMutationSpec::Mixed.from_xml('<p><a v="1"/></p>')

      expect { model.element_order << "x" }.not_to raise_error
    end
  end

  describe "empty collection assigned after parse" do
    it "emits a blank element under render_empty: :as_blank" do
      model = ParsedModelMutationSpec::EmptyColl.from_xml("<s><lead>L</lead></s>")
      model.blank_topic = []

      expect(model.to_xml).to include("<blank")
    end

    it "emits a nil element under render_empty: :as_nil" do
      model = ParsedModelMutationSpec::EmptyColl.from_xml("<s><lead>L</lead></s>")
      model.nil_topic = []

      expect(model.to_xml).to include("<nil")
    end

    it "emits nothing without render_empty" do
      model = ParsedModelMutationSpec::EmptyColl.from_xml("<s><lead>L</lead></s>")
      model.plain_topic = []

      expect(model.to_xml).not_to include("<plain")
    end
  end

  # A collection set to nil is never iterated, so it must be counted as one
  # element rather than measured for length.
  describe "collection set to nil after parse" do
    it "renders it as a nil element under render_nil" do
      model = ParsedModelMutationSpec::NilColl
        .from_xml("<s><lead>L</lead><item>x</item></s>")
      model.items = nil

      expect(model.to_xml).to include("nil=\"true\"")
    end

    it "emits nothing when the element was absent" do
      model = ParsedModelMutationSpec::NilColl.from_xml("<s><lead>L</lead></s>")
      model.items = nil

      expect(model.to_xml).not_to include("<item")
    end
  end

  # Pushing onto a default collection never reaches the setter, so the
  # attribute still reads as "using default" while holding real data.
  describe "default collection mutated in place" do
    it "emits the pushed item on a built model" do
      model = ParsedModelMutationSpec::DefaultColl.new { |m| m.lead = "L" }
      model.items << "x"

      expect(model.to_xml).to include("<item>x</item>")
    end

    it "emits the pushed item on a parsed model" do
      model = ParsedModelMutationSpec::DefaultColl
        .from_xml("<s><lead>L</lead></s>")
      model.items << "y"

      expect(model.to_xml).to include("<item>y</item>")
    end

    it "emits nothing when the default collection stays empty" do
      model = ParsedModelMutationSpec::DefaultColl
        .from_xml("<s><lead>L</lead></s>")

      expect(model.to_xml).not_to include("<item")
    end
  end

  # A derived attribute always reads as "using default", so the default
  # guard has to exempt it the way RenderPolicy does.
  describe "derived attribute on an ordered mapping" do
    it "is emitted whether or not element_order is populated" do
      empty_order = ParsedModelMutationSpec::DerivedOrdered.from_xml("<s/>")
      with_order = ParsedModelMutationSpec::DerivedOrdered
        .from_xml("<s><lead>L</lead></s>")

      expect(empty_order.to_xml).to include("<calc>D</calc>")
      expect(with_order.to_xml).to include("<calc>D</calc>")
    end
  end

  describe "delegated element set after parse" do
    it "emits the delegated value" do
      model = ParsedModelMutationSpec::Delegating.from_xml("<d><other>o</other></d>")
      model.glaze = ParsedModelMutationSpec::Glaze.new(color: "red")

      expect(model.to_xml).to include("red")
    end
  end

  describe "custom-method element rule on an ordered mapping" do
    it "serializes without raising" do
      model = ParsedModelMutationSpec::CustomMethod
        .from_xml("<c><label>L:x</label><name>x</name></c>")

      expect { model.to_xml }.not_to raise_error
    end

    # A custom `to:` emits the whole collection itself and is invoked once
    # per matching entry, so one entry must mean one invocation.
    it "invokes a custom collection transform once, not once per item" do
      model = ParsedModelMutationSpec::CustomColl.from_xml("<p><item>a</item></p>")
      model.items = %w[a b]

      expect(model.to_xml.scan("<item>").size).to eq(2)
    end
  end

  # Two rules mapping one element name cannot be told apart by the ordered
  # dispatcher, which resolves an entry to the first matching rule. That is
  # a pre-existing limitation and this spec does not pin its output; what it
  # does pin is that neither value goes missing.
  describe "two element rules sharing one serialized name" do
    it "emits both values when built" do
      model = ParsedModelMutationSpec::AmbiguousNames.new do |m|
        m.a = ParsedModelMutationSpec::SameNameA.new(v: "1")
        m.b = ParsedModelMutationSpec::SameNameB.new(w: "2")
      end

      expect(model.to_xml).to include('v="1"')
      expect(model.to_xml).to include('w="2"')
    end

    it "emits a value set after parsing" do
      model = ParsedModelMutationSpec::AmbiguousNames
        .from_xml('<p><same v="1"/></p>')
      model.b = ParsedModelMutationSpec::SameNameB.new(w: "2")

      expect(model.to_xml).to include('w="2"')
    end
  end

  describe "delegated element with name aliases" do
    it "keeps the parsed document order" do
      model = ParsedModelMutationSpec::DelegatingAlias
        .from_xml("<d><other>o</other><old-x>V</old-x></d>")

      xml = model.to_xml
      expect(xml).to include("V")
      expect(xml.index("other")).to be < xml.index("V")
    end
  end

  describe "builder-block construction" do
    it "emits attributes supplied by hash in declaration order" do
      model = ParsedModelMutationSpec::EmptyColl.new(lead: "L") do |m|
        m.plain_topic = ["t"]
      end

      xml = model.to_xml
      expect(xml.index("<lead")).to be < xml.index("<plain")
    end
  end
end
