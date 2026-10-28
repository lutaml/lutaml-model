# frozen_string_literal: true

require "spec_helper"

# #1031: wildcard attribute families — every attribute no explicit
# map_attribute claims and that matches the pattern lands in a Hash and
# is emitted back after the mapped attributes on serialization.
RSpec.describe "map_all_attributes" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :data_attributes, :hash

      xml do
        element "mn"
        map_attribute "name", to: :name
        map_all_attributes to: :data_attributes, matching: /\A(data-|aria-|on)/
      end
    end
  end

  let(:stubbed) do
    stub_const("MapAllAttributesModel", model_class)
    MapAllAttributesModel
  end

  it "captures unclaimed, pattern-matching attributes into the Hash" do
    xml = '<mn name="x" data-title="T" onclick="f()" aria-label="L" unre="nope"/>'
    model = stubbed.from_xml(xml)

    expect(model.name).to eq("x")
    expect(model.data_attributes).to eq(
      "data-title" => "T", "onclick" => "f()", "aria-label" => "L",
    )
  end

  it "never lets mapped names leak into the remainder" do
    xml = '<mn name="x" data-name="D"/>'
    model = stubbed.from_xml(xml)

    expect(model.data_attributes).to eq("data-name" => "D")
  end

  it "emits the remainder after the mapped attributes on serialization" do
    model = stubbed.from_xml(
      '<mn name="x" data-title="T" onclick="f()"/>',
    )
    out = model.to_xml

    expect(out).to include('name="x"')
    expect(out).to include('data-title="T"')
    expect(out).to include('onclick="f()"')
    expect(out.index("name=")).to be < out.index("data-title=")
  end

  it "round-trips losslessly" do
    xml = '<mn name="x" data-title="T" onclick="f()" aria-label="L"/>'
    model = stubbed.from_xml(xml)
    round_tripped = stubbed.from_xml(model.to_xml)

    expect(round_tripped.data_attributes).to eq(model.data_attributes)
    expect(round_tripped.name).to eq(model.name)
  end

  it "emits nothing when the remainder is empty" do
    model = stubbed.from_xml('<mn name="x"/>')
    out = model.to_xml

    expect(out).not_to include("data-")
  end

  it "captures every unclaimed attribute when no pattern is given" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :other_attributes, :hash

      xml do
        element "el"
        map_attribute "name", to: :name
        map_all_attributes to: :other_attributes
      end
    end
    stub_const("MapAllNoPatternModel", klass)

    model = klass.from_xml('<el name="x" zeta="1"/>')

    expect(model.other_attributes).to eq("zeta" => "1")
  end

  it "is inherited by a subclass along with the other mappings" do
    stub_const("MapAllAttributesChild", Class.new(stubbed))

    model = MapAllAttributesChild.from_xml('<mn name="x" data-title="T"/>')

    expect(model.data_attributes).to eq("data-title" => "T")
    expect(model.to_xml).to include('data-title="T"')
  end
end
