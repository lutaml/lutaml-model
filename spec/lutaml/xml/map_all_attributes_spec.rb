# frozen_string_literal: true

require "spec_helper"

# Capture-everything model: explicitly mapped attributes are excluded from
# the remainder; namespaced attributes are never captured (#1031).
class WildcardBook < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :other_attributes, :hash

  xml do
    element "book"
    map_attribute "id", to: :id
    map_all_attributes to: :other_attributes
  end
end

# Pattern-filtered model: only attributes matching the Regexp are captured.
class WildcardTag < Lutaml::Model::Serializable
  attribute :other_attributes, :hash

  xml do
    element "tag"
    map_all_attributes to: :other_attributes, matching: /\Adata-/
  end
end

# Coexistence: map_all (raw content) and map_all_attributes are independent.
class WildcardMixed < Lutaml::Model::Serializable
  attribute :text, :string, collection: true
  attribute :other_attributes, :hash

  xml do
    element "mixed"
    mixed_content
    map_content to: :text
    map_all_attributes to: :other_attributes
  end
end

RSpec.describe "map_all_attributes" do
  let(:namespaced_input) do
    '<book xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' \
      'id="b1" data-foo="1" onclick="x()" xsi:type="t"/>'
  end

  it "captures unclaimed attributes into the target hash" do
    book = WildcardBook.from_xml(
      '<book id="b1" data-foo="1" onclick="x()"/>',
    )

    expect(book.id).to eq("b1")
    expect(book.other_attributes).to eq("data-foo" => "1", "onclick" => "x()")
  end

  it "never captures namespaced attributes" do
    book = WildcardBook.from_xml(namespaced_input)

    expect(book.other_attributes).to eq("data-foo" => "1", "onclick" => "x()")
  end

  it "round-trips captured attributes on serialize" do
    book = WildcardBook.from_xml(
      '<book id="b1" data-foo="1" onclick="x()"/>',
    )
    output = book.to_xml

    expect(output).to include('id="b1"')
    expect(output).to include('data-foo="1"')
    expect(output).to include('onclick="x()"')
  end

  it "omits the remainder entirely when nothing was captured" do
    output = WildcardBook.from_xml('<book id="b1"/>').to_xml

    expect(output).to include('id="b1"')
    expect(output).not_to include("data-")
  end

  it "filters captured attributes by the matching pattern" do
    tag = WildcardTag.from_xml('<tag data-only="y" onclick="nope" z="1"/>')

    expect(tag.other_attributes).to eq("data-only" => "y")
    expect(tag.to_xml).to include('data-only="y"')
    expect(tag.to_xml).not_to include("onclick")
  end

  it "coexists with map_content (attributes and content are independent)" do
    mixed = WildcardMixed.from_xml('<mixed data-a="1">hello</mixed>')

    expect(mixed.text).to eq(["hello"])
    expect(mixed.other_attributes).to eq("data-a" => "1")
    expect(mixed.to_xml).to include("hello").and include('data-a="1"')
  end

  it "is excluded from the leptris plan fast path (general path parity)" do
    plan = Lutaml::Xml::Leptris::PlanCompiler.compile(WildcardBook, :default)

    expect(plan).to be_nil
  end
end
