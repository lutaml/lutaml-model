# frozen_string_literal: true

require "spec_helper"
require "lutaml/rdf"

RSpec.describe Lutaml::Rdf::TermDefinition do
  it "simple term maps to name => id" do
    td = described_class.new(name: "name", id: "http://example.org/name")
    expect(td.to_context_hash).to eq("name" => "http://example.org/name")
  end

  it "term with type includes @type" do
    td = described_class.new(name: "date", id: "http://example.org/date",
                             type: "xsd:date")
    expect(td.to_context_hash).to eq("date" => {
                                       "@id" => "http://example.org/date", "@type" => "xsd:date"
                                     })
  end

  it "term with container includes @container" do
    td = described_class.new(name: "labels", id: "http://example.org/labels",
                             container: :language)
    expect(td.to_context_hash).to eq("labels" => {
                                       "@id" => "http://example.org/labels", "@container" => "@language"
                                     })
  end

  it "term with language includes @language" do
    td = described_class.new(name: "title", id: "http://example.org/title",
                             language: "en")
    expect(td.to_context_hash).to eq("title" => {
                                       "@id" => "http://example.org/title", "@language" => "en"
                                     })
  end

  it "term with reverse includes @reverse" do
    td = described_class.new(name: "parent", id: "http://example.org/parent",
                             reverse: true)
    expect(td.to_context_hash).to eq("parent" => {
                                       "@id" => "http://example.org/parent", "@reverse" => true
                                     })
  end

  it "complex term includes all fields" do
    td = described_class.new(
      name: "date",
      id: "http://example.org/date",
      type: "xsd:date",
      container: :set,
    )
    hash = td.to_context_hash
    expect(hash["date"]).to eq({ "@id" => "http://example.org/date",
                                 "@type" => "xsd:date", "@container" => "@set" })
  end
end
