# frozen_string_literal: true

require "lutaml/model"
require "json"
require "yaml"
require_relative "../../support/lml_export_fixtures"

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

  describe "v1 sequence determinism" do
    let(:script) do
      <<~RUBY
        require "lutaml/model"
        require "json"
        require "./spec/support/lml_export_fixtures"
        d = Lutaml::Model::Lml::Exporter.export(LmlExportFixtures::ChoiceSequence)
        puts JSON.generate([d.mappings["xml"]["sequence"], d.checksum])
      RUBY
    end

    def run_fresh
      out = IO.popen([RbConfig.ruby, "-Ilib", "-Ispec", "-e", script], err: %i[child out], &:read)
      JSON.parse(out.lines.last)
    end

    it "gives identical v1 sequence bytes and checksum in separate processes" do
      first = run_fresh
      second = run_fresh
      expect(second).to eq(first)
      expect(first.first.to_s).not_to match(/#<|0x[0-9a-f]{6,}/)
    end

    it "projects the sequence structurally" do
      sequence = export(LmlExportFixtures::ChoiceSequence).mappings["xml"]["sequence"]
      expect(sequence.first).to include("kind" => "sequence")
      expect(sequence.first["members"].map { |m| m["kind"] }).to eq(%w[element choice])
    end

    it "leaves models without a sequence unchanged" do
      expect(export(unit_class).mappings["xml"]).not_to have_key("sequence")
    end
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

  describe "ordered and mixed content" do
    let(:descriptor) { { "member" => "__lml_content", "version" => 1 } }

    it "exports declarative ordered content (Mml::V4::Math shape)" do
      document = export(LmlExportFixtures::MathShape)
      expect(document.mappings["xml"]).to include(
        "ordered" => true, "ordered_content" => descriptor,
      )
    end

    it "exports declarative mixed content" do
      document = export(LmlExportFixtures::MixedShape)
      expect(document.mappings["xml"]).to include("ordered_content" => descriptor)
    end

    it "exports the v1 ordered fixture" do
      expect(export(LmlSpecFixtures::OrderedMixed).mappings["xml"])
        .to include("ordered_content" => descriptor)
    end

    it "still rejects order driven by an executable callback" do
      expect { export(LmlExportFixtures::OrderedWithCallback) }.to raise_error(
        Lutaml::Model::Lml::RejectedError, /imperative_element_order/
      )
    end

    it "rejects a source member named __lml_content" do
      expect { export(LmlExportFixtures::ReservedMember) }.to raise_error(
        Lutaml::Model::Lml::RejectedError, /reserved_member/
      )
    end

    it "declares the descriptor on the portable document" do
      projected = Lutaml::Model::Lml::Exporter.project(LmlExportFixtures::MathShape)
      expect(projected["ordered_content"]).to eq(descriptor)
    end
  end

  describe "render policies" do
    it "keeps render_empty and value_map on JSON rules" do
      rules = export(LmlExportFixtures::RenderPolicies).mappings["json"]["rules"]
      expect(rules).to include({ "key" => ["x"], "to" => "x", "render_empty" => true })
      y_rule = rules.find { |rule| rule["key"] == ["y"] }
      expect(y_rule["value_map"]["to"]["empty"]).to eq("nil")
    end

    it "keeps render_empty and render_default on XML rules" do
      rule = export(LmlExportFixtures::PortableRender).mappings["xml"]["rules"].first
      expect(rule).to include("render_empty" => true, "render_default" => true)
    end
  end

  describe "portable v2 projection" do
    let(:projected) { Lutaml::Model::Lml::Exporter.project(LmlExportFixtures::PortableRender) }

    it "tags types, defaults, enums and collection bounds" do
      by_name = projected["attributes"].to_h { |attr| [attr["name"], attr] }
      expect(projected).to include("lml" => 2, "register" => "default")
      expect(by_name["x"]).to include("type" => { "kind" => "builtin", "name" => "string" },
                                      "default" => { "present" => false }, "collection" => false)
      expect(by_name["count"]["default"]).to eq({ "present" => true, "value" => 3 })
      expect(by_name["kind"]["values"]).to eq(%w[a b])
      expect(by_name["items"]["collection"]).to eq({ "min" => 1, "max" => 4 })
    end

    it "resolves render policies and namespace modes per rule" do
      rule = projected["mappings"]["xml"]["rules"].first
      expect(rule).to include(
        "render" => { "nil" => "as_blank", "empty" => "as_empty", "default" => true },
        "namespace" => { "mode" => "inherit" },
      )
    end

    it "names unsupported constructs" do
      expect { Lutaml::Model::Lml::Exporter.project(LmlExportFixtures::TransformRule) }
        .to raise_error(Lutaml::Model::Lml::RejectedError, /unsupported_mapping/)
      expect { Lutaml::Model::Lml::Exporter.project(LmlExportFixtures::NonFiniteFloatDefault) }
        .to raise_error(Lutaml::Model::Lml::RejectedError, /non_serializable_default/)
    end

    it "exports float as the builtin with a canonical shortest-round-trip string default" do
      document = Lutaml::Model::Lml::Exporter.project(LmlExportFixtures::FloatAttr)
      by_name = document["attributes"].to_h { |attribute| [attribute["name"], attribute] }
      expect(by_name.values.map { |attribute| attribute["type"] }).to all(eq("kind" => "builtin", "name" => "float"))
      expect(by_name["f"]["default"]).to eq("present" => false)
      expect(by_name.slice("ratio", "tiny", "whole").transform_values { |a| a["default"] }).to eq(
        "ratio" => { "present" => true, "value" => "0.71" },
        "tiny" => { "present" => true, "value" => "1.0e-5" },
        "whole" => { "present" => true, "value" => "3.0" },
      )
      expect { Lutaml::Model::Lml::DocumentValidator.validate!(document, kind: :document) }.not_to raise_error
    end
  end

  it "rejects a non-serializable class" do
    expect { export(String) }.to raise_error(
      Lutaml::Model::Lml::RejectedError,
      /not_serializable/,
    )
  end
end
