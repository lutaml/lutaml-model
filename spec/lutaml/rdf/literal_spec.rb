# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::Literal do
  describe "plain literal" do
    subject(:lit) { described_class.new("hello") }

    it "stores value" do
      expect(lit.value).to eq("hello")
    end

    it "has no datatype" do
      expect(lit.datatype).to be_nil
    end

    it "has no language" do
      expect(lit.language).to be_nil
    end

    it "serializes to Turtle" do
      expect(lit.to_turtle).to eq('"hello"')
    end

    it "serializes to JSON-LD as plain value" do
      expect(lit.to_jsonld_term).to eq("hello")
    end
  end

  describe "language-tagged literal" do
    subject(:lit) { described_class.new("hello", language: "en") }

    it "serializes to Turtle with language tag" do
      expect(lit.to_turtle).to eq('"hello"@en')
    end

    it "serializes to JSON-LD with @language" do
      expect(lit.to_jsonld_term).to eq({ "@value" => "hello",
                                         "@language" => "en" })
    end
  end

  describe "typed literal" do
    subject(:lit) { described_class.new("2024-01-01", datatype: "http://www.w3.org/2001/XMLSchema#date") }

    it "serializes to Turtle with datatype" do
      expect(lit.to_turtle).to eq('"2024-01-01"^^<http://www.w3.org/2001/XMLSchema#date>')
    end

    it "serializes to JSON-LD with @type" do
      expect(lit.to_jsonld_term).to eq({ "@value" => "2024-01-01",
                                         "@type" => "http://www.w3.org/2001/XMLSchema#date" })
    end
  end

  describe "special character escaping" do
    it "escapes quotes" do
      lit = described_class.new('has "quotes"')
      expect(lit.to_turtle).to eq('"has \\"quotes\\""')
    end

    it "escapes newlines" do
      lit = described_class.new("line1\nline2")
      expect(lit.to_turtle).to eq('"line1\\nline2"')
    end

    it "escapes backslashes" do
      lit = described_class.new("back\\slash")
      expect(lit.to_turtle).to eq('"back\\\\slash"')
    end

    it "escapes tabs" do
      lit = described_class.new("tab\there")
      expect(lit.to_turtle).to eq('"tab\\there"')
    end
  end

  describe "equality" do
    it "equals literal with same value, datatype, and language" do
      a = described_class.new("hello", language: "en")
      b = described_class.new("hello", language: "en")
      expect(a).to eq(b)
    end

    it "does not equal with different language" do
      a = described_class.new("hello", language: "en")
      b = described_class.new("hello", language: "fr")
      expect(a).not_to eq(b)
    end

    it "does not equal with different datatype" do
      a = described_class.new("1", datatype: "xsd:integer")
      b = described_class.new("1", datatype: "xsd:string")
      expect(a).not_to eq(b)
    end
  end
end
