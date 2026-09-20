# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/lutaml/model"

module InstantiateMapping
  class Part < Lutaml::Model::Serializable
    attribute :label, :string
    attribute :count, :integer
  end

  class Widget < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :flag, :boolean
    attribute :part, Part
    attribute :tags, :string, collection: true

    key_value do
      map "name", to: :name
      map "flag", to: :flag
      map "part", to: :part
      map "tags", to: :tags
    end
  end
end

RSpec.describe "Serializable.instantiate" do
  it "hydrates attributes from primitives" do
    widget = InstantiateMapping::Widget.instantiate("name" => "w", "flag" => true,
                                                    "tags" => %w[a b])
    expect(widget.name).to eq("w")
    expect(widget.flag).to be(true)
    expect(widget.tags).to eq(%w[a b])
  end

  it "accepts pre-built instances for typed attributes" do
    part = InstantiateMapping::Part.instantiate(label: "p", count: 2)
    widget = InstantiateMapping::Widget.instantiate(name: "w", part: part)

    expect(widget.part).to equal(part)
  end

  it "keeps defaults for absent keys and reports them as defaults" do
    widget = InstantiateMapping::Widget.instantiate
    # Absent scalars read as the uninitialized sentinel, exactly like the
    # XML fast path; serialization omits them either way.
    expect(Lutaml::Model::Utils.uninitialized?(widget.name) ||
           widget.name.nil?).to be(true)
    expect(widget).to be_using_default(:name)
  end

  it "marks set attributes as explicitly set" do
    widget = InstantiateMapping::Widget.instantiate(name: "w")
    expect(widget).not_to be_using_default(:name)
  end

  it "serializes identically to from_hash" do
    input = { "name" => "w", "flag" => false,
              "part" => { "label" => "p", "count" => 3 },
              "tags" => ["x"] }
    from_hash = InstantiateMapping::Widget.from_hash(input)

    part = InstantiateMapping::Part.instantiate(input["part"])
    fast = InstantiateMapping::Widget.instantiate(
      name: "w", flag: false, part: part, tags: ["x"]
    )

    expect(fast.to_hash).to eq(from_hash.to_hash)
  end

  it "raises on unknown attribute names" do
    expect { InstantiateMapping::Widget.instantiate(bogus: 1) }
      .to raise_error(Lutaml::Model::Error, /unknown attribute/)
  end
end
