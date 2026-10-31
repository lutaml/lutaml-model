# frozen_string_literal: true

require "lutaml/model"
require "json"
require "yaml"

# lutaml-model#1033 Phase 1: the LML declaration exporter. Ruby model →
# neutral LML document (attributes + per-format mappings), checksummed
# over the canonical form, with the round-trip gate pinned from day one.
# Named fixture classes: the document addresses models by class path,
# so anonymous classes are unnameable (the exporter rejects them).
module LmlSpecFixtures # rubocop:disable Lint/ConstantDefinitionInBlock -- named fixtures, see below
  class Dimension < Lutaml::Model::Serializable
    attribute :si_name, :string
    attribute :si_symbol, :string

    xml do
      root "dimension"
      map_attribute "siName", to: :si_name
      map_element "siSymbol", to: :si_symbol
    end
  end

  class Unit < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :quantity_type, :string, values: %w[length mass time]
    attribute :dimensions, Dimension, collection: 0..10
    attribute :symbol, :string, default: "u"

    xml do
      root "unit"
      map_attribute "id", to: :id
      map_attribute "quantityType", to: :quantity_type
      map_element "dimension", to: :dimensions
      map_element "symbol", to: :symbol
    end

    json do
      map "id", to: :id
      map "quantityType", to: :quantity_type
      map "dimensions", to: :dimensions
      map "symbol", to: :symbol
    end
  end

  class OrderedMixed < Lutaml::Model::Serializable
    attribute :text, :string
    attribute :other, :string

    xml do
      root "mixed", ordered: true
      map_element "text", to: :text
      map_element "other", to: :other
    end
  end
end

RSpec.describe Lutaml::Model::Lml do
  let(:unit_class) { LmlSpecFixtures::Unit }

  def export(klass)
    described_class.export(klass)
  end

  it "projects attributes with types, collections, defaults and enums" do
    document = export(unit_class)
    dimensions = document.attributes.find { |attr| attr["name"] == "dimensions" }
    symbol = document.attributes.find { |attr| attr["name"] == "symbol" }
    quantity = document.attributes.find { |attr| attr["name"] == "quantity_type" }

    expect(dimensions).to include(
      "type" => "LmlSpecFixtures::Dimension",
      "collection" => { "min" => 0, "max" => 10 },
    )
    expect(symbol).to include("default" => "u")
    expect(quantity).to include("values" => %w[length mass time])
  end

  it "projects per-format mappings, not per-DSL blocks" do
    document = export(unit_class)
    expect(document.mappings.keys).to eq(["xml", "json"])

    xml = document.mappings["xml"]
    expect(xml["root"]).to include("element" => "unit")
    expect(xml["rules"]).to include(
      { "kind" => "attribute", "name" => ["id"], "to" => "id" },
    )
    expect(document.mappings["json"]["rules"]).to include(
      { "key" => ["id"], "to" => "id" },
    )
  end

  it "pins a checksum over the canonical form" do
    document = export(unit_class)
    expect(document.checksum).to start_with("sha256:")
    expect(export(unit_class).checksum).to eq(document.checksum)
  end

  it "is byte-stable across renders and key order" do
    document = export(unit_class)
    expect(document.to_yaml).to include("model:")
    expect(JSON.parse(document.to_json)).to eq(JSON.parse(document.canonical_json))
  end

  it "round-trips: the document re-derives the model" do
    document = export(unit_class)
    verified = described_class.verify(
      Lutaml::Model::Lml::Document.from_hash(document.to_h),
    )
    expect(verified.checksum).to eq(document.checksum)
  end

  it "rejects lambda defaults" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :x, :string, default: -> { "d" }
    end
    expect { export(klass) }.to raise_error(
      Lutaml::Model::Lml::RejectedError,
      /lambda_default/,
    )
  end

  it "rejects a custom initialize" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :x, :string

      def initialize(attrs = {})
        super
      end
    end
    expect { export(klass) }.to raise_error(
      Lutaml::Model::Lml::RejectedError,
      /custom_initialize/,
    )
  end

  it "rejects ordered content with no declared sequence" do
    expect { export(LmlSpecFixtures::OrderedMixed) }.to raise_error(
      Lutaml::Model::Lml::RejectedError,
      /imperative_element_order/,
    )
  end

  it "rejects a non-serializable class" do
    expect { export(String) }.to raise_error(
      Lutaml::Model::Lml::RejectedError,
      /not_serializable/,
    )
  end
end
