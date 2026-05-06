# frozen_string_literal: true

require "spec_helper"
require "lutaml/turtle"

RSpec.describe Lutaml::Turtle::Adapter do
  describe ".parse" do
    it "parses valid Turtle into RDF::Graph" do
      turtle = <<~TURTLE
        @prefix skos: <http://www.w3.org/2004/02/skos/core#> .
        <http://example.org/1> a skos:Concept ;
          skos:prefLabel "test"@en .
      TURTLE

      graph = described_class.parse(turtle)
      expect(graph).to be_a(RDF::Graph)
      expect(graph.count).to eq(2)
    end

    it "produces empty graph for invalid Turtle" do
      # RDF::Turtle::Reader logs errors instead of raising
      graph = described_class.parse("not valid turtle !!!")
      expect(graph).to be_a(RDF::Graph)
      expect(graph.count).to eq(0)
    end
  end

  describe "#to_turtle" do
    it "returns string data as-is" do
      adapter = described_class.new("some turtle content")
      expect(adapter.to_turtle).to eq("some turtle content")
    end

    it "serializes RDF::Enumerable to string" do
      graph = RDF::Graph.new
      graph << RDF::Statement.new(
        RDF::URI("http://example.org/1"),
        RDF::URI("http://www.w3.org/2004/02/skos/core#prefLabel"),
        RDF::Literal.new("test"),
      )
      adapter = described_class.new(graph)
      result = adapter.to_turtle
      expect(result).to include("http://example.org/1")
      expect(result).to include("test")
    end
  end
end
