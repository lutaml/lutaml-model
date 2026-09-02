# frozen_string_literal: true

require "spec_helper"

# lutaml-model#765: two element rules mapped to one collection attribute
# (spelling tolerance, e.g. metanorma's editorial-group/editorialgroup).
# Parse must merge the spellings' content in document order — never drop
# the first silently — and serialization must emit the value once, under
# the first declared spelling.
module SharedElementRulesSpec
  class Both < Lutaml::Model::Serializable
    attribute :items, :string, collection: true

    xml do
      root "r"
      map_element "a", to: :items
      map_element "b", to: :items
    end
  end
end

RSpec.describe "multiple element rules on one attribute" do
  it "appends both spellings in document order" do
    expect(SharedElementRulesSpec::Both.from_xml("<r><a>one</a><b>two</b></r>").items)
      .to eq(["one", "two"])
  end

  it "appends in document order when the second spelling comes first" do
    expect(SharedElementRulesSpec::Both.from_xml("<r><b>two</b><a>one</a></r>").items)
      .to eq(["two", "one"])
  end

  it "keeps document order across interleaved spellings" do
    xml = "<r><a>1</a><b>2</b><a>3</a><b>4</b></r>"
    expect(SharedElementRulesSpec::Both.from_xml(xml).items).to eq(%w[1 2 3 4])
  end

  it "parses a document that only uses the first spelling" do
    expect(SharedElementRulesSpec::Both.from_xml("<r><a>one</a></r>").items)
      .to eq(["one"])
  end

  it "parses a document that only uses the second spelling" do
    expect(SharedElementRulesSpec::Both.from_xml("<r><b>two</b></r>").items)
      .to eq(["two"])
  end

  it "serializes the value once, under the first declared spelling" do
    xml = SharedElementRulesSpec::Both.new(items: %w[one two]).to_xml
    expect(xml.scan(/<(a|b)>/).flatten).to eq(%w[a a])
    expect(xml).to include("<a>one</a>").and include("<a>two</a>")
  end

  it "round-trips through both spellings without losing content" do
    doc = SharedElementRulesSpec::Both.from_xml("<r><a>one</a><b>two</b></r>")
    reparsed = SharedElementRulesSpec::Both.from_xml(doc.to_xml)
    expect(reparsed.items).to eq(%w[one two])
  end

  it "keeps the mapping usable when the attribute also has a default" do
    both = SharedElementRulesSpec::Both.from_xml("<r/>")
    expect(both.items).to eq([])
  end
end
