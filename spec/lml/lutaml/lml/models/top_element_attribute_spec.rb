# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lml_spec_setup"

RSpec.describe Lutaml::Lml::TopElementAttribute do
  describe "inheritance" do
    it "inherits from Lutaml::Model::Serializable" do
      expect(described_class).to be < Lutaml::Model::Serializable
    end
  end

  describe "extended attributes" do
    it "has properties collection" do
      attr = described_class.new
      expect(attr.properties).to eq([])
    end

    it "defaults value to nil" do
      attr = described_class.new
      expect(attr.value).to be_nil
    end

    it "has attributes collection" do
      attr = described_class.new
      expect(attr.attributes).to eq([])
    end

    it "has extended boolean" do
      attr = described_class.new
      expect(attr.extended).to be_nil
      attr.extended = true
      expect(attr.extended).to eq(true)
    end

    it "has instances collection" do
      attr = described_class.new
      expect(attr.instances).to eq([])
    end
  end

  describe "with nested properties" do
    it "holds nested TopElementAttribute as properties" do
      prop = described_class.new(name: "description", value: "A description")
      attr = described_class.new(name: "dev_id", type: "String", properties: [prop])
      expect(attr.properties.first.name).to eq("description")
    end
  end

  describe "key_value mapping" do
    # Declaring a mapping block replaces the defaults, so an attribute added
    # later is silently dropped from every key-value format unless it is also
    # mapped. This is the guard for that.
    # Each format builds its own mapping object from the one block, so every
    # format is checked rather than trusting YAML to stand for the rest.
    Lutaml::Model::FormatRegistry.key_value_formats.each do |format|
      it "maps every declared attribute for #{format}" do
        mapped = described_class.mappings_for(format).mappings.map(&:to)

        expect(mapped.sort).to eq(described_class.attributes.keys.sort)
      end

      it "maps each attribute under its own name for #{format}" do
        described_class.mappings_for(format).mappings.each do |rule|
          expect(rule.name).to eq(rule.to.to_s)
        end
      end
    end
  end

  describe "attribute value round trip" do
    def unwrap(value)
      return value.map { |item| unwrap(item) } if value.is_a?(Array)

      value.is_a?(Lutaml::Lml::LiteralValue) ? value.value : value
    end

    def round_trip(name, body, format)
      lml = "instances {\n  Product \"p\" {\n    #{body}\n  }\n}\n"
      doc = Lutaml::Lml::Pipeline.call(StringIO.new(lml))
      reloaded = Lutaml::Lml::Document.public_send(
        :"from_#{format}", doc.public_send(:"to_#{format}")
      )
      attr = reloaded.instances.instances.first.attributes.find { |a| a.name == name }
      raise "no attribute named #{name.inspect}" unless attr

      unwrap(attr.value)
    end

    # A map literal's value can only be boolean | reference | range | number |
    # quoted_string (grammar `key_value_pair` -> `value`). One row per shape,
    # because a corpus that stops one shape short is how the list case survived.
    #
    # Note the range row expects string bounds while the integer row expects a
    # real Integer: range endpoints come off the parser as text and are never
    # coerced. That asymmetry is the parser's, and these rows pin it.
    {
      "string" => [%q(id = "component_id"), { id: "component_id" }],
      "single-quoted" => [%q(id = 'component_id'), { id: "component_id" }],
      "boolean" => [%q(flag = true), { flag: true }],
      "integer" => [%q(n = 42), { n: 42 }],
      "float" => [%q(f = 1.5), { f: 1.5 }],
      "reference" => [%q(r = reference:(Product.id)), { r: { reference: "Product.id" } }],
      "range" => [%q(r = 1..9), { r: { range: { start: "1", end: "9" } } }],
      "no-equals pair" => [%q(id "component_id"), { id: "component_id" }],
    }.each do |shape, (pair, expected)|
      it "reloads a map value with a #{shape} through YAML" do
        body = "columns {\n      #{pair}\n    }"
        expect(round_trip("columns", body, :yaml)).to eq(expected)
      end
    end

    # The defect this change fixes: these raised CollectionTrueMissingError out
    # of Document.from_yaml, which is the CLI's `-i yaml` input path.
    {
      "strings" => [%q(tags = ["a", "b"]), ["a", "b"]],
      "mixed scalar types" => [%q(tags = ["a", 1, true]), ["a", 1, true]],
      "one element" => [%q(tags = ["only"]), ["only"]],
    }.each do |shape, (body, expected)|
      %i[yaml json].each do |format|
        it "reloads a list of #{shape} through #{format.upcase}" do
          expect(round_trip("tags", body, format)).to eq(expected)
        end
      end
    end

    it "reloads a list of references through YAML" do
      expect(round_trip("tags", %q(tags = [reference:(A.b)]), :yaml))
        .to eq([{ reference: "A.b" }])
    end

    # lutaml-model#746 fixed the present? gate: custom from methods now
    # receive empty values, so an empty sequence survives as a present
    # (non-nil) value.
    it "preserves an empty list" do
      expect(round_trip("tags", %q(tags = []), :yaml)).to eq([])
    end

    it "keeps a false literal, which is not the same as an absent value" do
      expect(round_trip("flag", %q(flag = false), :yaml)).to eq(false)
    end

    # Asserts the absence of the key, not the absence of the text. An attribute
    # whose name merely contains "value" would defeat a substring check while
    # the guard is working perfectly.
    it "omits the value key entirely when there is no value" do
      attr = described_class.new(name: "value_kind", type: "ValidationCheck")

      expect(YAML.safe_load(attr.to_yaml)).not_to have_key("value")
    end
  end
end
