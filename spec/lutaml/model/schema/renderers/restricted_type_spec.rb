# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema/definitions"
require "lutaml/model/schema/renderers/restricted_type"

RSpec.describe Lutaml::Model::Schema::Renderers::RestrictedType do
  let(:defs) { Lutaml::Model::Schema::Definitions }

  it "renders min/max facets in the cast body" do
    spec = defs::RestrictedType.new(
      class_name: "PositiveInt",
      parent_class: "Lutaml::Model::Type::Integer",
      base_class: "integer",
      facets: defs::Facet.new(min_inclusive: 1, max_inclusive: 100),
    )

    output = described_class.render(spec)

    expect(output).to include("class PositiveInt < Lutaml::Model::Type::Integer")
    expect(output).to include("def self.cast(value, options = {})")
    expect(output).to include("options[:min] = 1")
    expect(output).to include("options[:max] = 100")
    expect(output).to include("value = super(value, options)")
  end

  it "renders enumerations facet" do
    spec = defs::RestrictedType.new(
      class_name: "Color",
      parent_class: "Lutaml::Model::Type::String",
      facets: defs::Facet.new(enumerations: %w[red green blue]),
    )

    output = described_class.render(spec)

    expect(output).to include('options[:values] = [super("red"), super("green"), super("blue")]')
    expect(output).not_to include("options[:min]")
  end

  it "renders pattern facet as a regexp literal" do
    spec = defs::RestrictedType.new(
      class_name: "Slug",
      parent_class: "Lutaml::Model::Type::String",
      facets: defs::Facet.new(pattern: "[a-z0-9-]+"),
    )

    output = described_class.render(spec)

    expect(output).to include("options[:pattern] = %r{[a-z0-9-]+}")
  end

  it "renders transform facet" do
    spec = defs::RestrictedType.new(
      class_name: "Upper",
      parent_class: "Lutaml::Model::Type::String",
      facets: defs::Facet.new,
      transform_facet: defs::TransformFacet.new(expression: "value.upcase"),
    )

    output = described_class.render(spec)

    expect(output).to include("value = value.upcase")
  end

  it "uses lazy register memoisation" do
    spec = defs::RestrictedType.new(
      class_name: "Tiny",
      parent_class: "Lutaml::Model::Type::Integer",
      facets: defs::Facet.new(max_inclusive: 5),
    )

    output = described_class.render(spec)

    expect(output).to include("@register ||= Lutaml::Model::Config.default_register")
  end
end
