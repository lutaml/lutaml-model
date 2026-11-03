# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/lml/materialization"
require "lutaml/model/lml/exporter"
require_relative "../../support/lml_materialization_fixtures"

RSpec.describe Lutaml::Model::Lml::Materialization do
  let(:fixtures) { LmlMaterializationFixtures }
  let(:order_id) { "Shop::Order@default" }
  let(:line_id) { "Shop::Line@default" }

  def build(bundle, **opts)
    described_class.build(bundle, namespace: Module.new, **opts)
  end

  it "needs no source constants" do
    expect(Object.const_defined?(:Shop)).to be(false)
    expect(build(fixtures.cyclic).keys).to eq([line_id, order_id])
    expect(Object.const_defined?(:Shop)).to be(false)
  end

  it "links nested and cyclic models by identity" do
    classes = build(fixtures.cyclic)
    order = classes[order_id]
    line = classes[line_id]

    expect(order.attributes[:lines].type).to equal(line)
    expect(order.attributes[:parent].type).to equal(order)
    expect(line.attributes[:order].type).to equal(order)
  end

  it "declares required, enum, default and collection bounds" do
    order = build(fixtures.cyclic)[order_id]
    line = build(fixtures.cyclic)[line_id]

    expect(order.attributes[:id].options[:required]).to be(true)
    expect(order.attributes[:status].enum_values).to eq(%w[open closed])
    expect(order.new.status).to eq("open")
    expect(line.attributes[:qty].resolved_collection).to eq(1..3)
    expect(order.attributes[:lines].resolved_collection.max).to eq(Float::INFINITY)
  end

  it "builds working models for a cyclic instance graph" do
    classes = build(fixtures.cyclic)
    order = classes[order_id].new(id: "1")
    order.lines = [classes[line_id].new(sku: "a", order: order)]

    expect(order.lines.first.order).to equal(order)
  end

  it "installs generated constants under the namespace only" do
    holder = Module.new
    classes = described_class.build(fixtures.cyclic, namespace: holder)

    expect(holder::Shop::Order).to equal(classes[order_id])
    expect(classes[order_id].name).to end_with("::Shop::Order")
  end

  it "keeps explicit contexts independent" do
    first = build(fixtures.cyclic)
    second = build(fixtures.cyclic)

    expect(first[order_id]).not_to equal(second[order_id])
    expect(first[order_id].attributes[:lines].type).to equal(first[line_id])
    expect(second[order_id].attributes[:lines].type).to equal(second[line_id])
  end

  it "re-exports the same attribute declarations from each context" do
    exported = ->(classes) { Lutaml::Model::Lml::Exporter.export(classes[order_id]).attributes }
    first = exported.call(build(fixtures.cyclic))
    second = exported.call(build(fixtures.cyclic))

    expect(first.map { |a| a["name"] }).to eq(%w[id status lines parent])
    expect(first.map { |a| a.except("type") }).to eq(second.map { |a| a.except("type") })
  end

  it "refuses a second build into the same namespace" do
    holder = Module.new
    described_class.build(fixtures.cyclic, namespace: holder)

    expect { described_class.build(fixtures.cyclic, namespace: holder) }
      .to raise_error(Lutaml::Model::Lml::RejectedError) { |e| expect(e.reason).to eq(:duplicate_id) }
  end

  describe "value type bindings" do
    it "uses the trusted binding" do
      sku = Class.new(Lutaml::Model::Type::String)
      classes = build(fixtures.with_value_type, type_bindings: { "Shop::Sku" => sku })

      expect(classes["Shop::Item@default"].attributes[:code].type).to equal(sku)
    end

    it "fails by name when the binding is missing" do
      expect { build(fixtures.with_value_type) }
        .to raise_error(Lutaml::Model::Lml::RejectedError, /Shop::Sku/) { |e| expect(e.reason).to eq(:missing_type_binding) }
    end
  end

  it "fails by name on an unknown builtin" do
    bundle = fixtures.bundle("A@default" => fixtures.model("A", [
                                                             { "name" => "x", "type" => { "kind" => "builtin", "name" => "nope" } },
                                                           ]))

    expect { build(bundle) }
      .to raise_error(Lutaml::Model::Lml::RejectedError, /nope/) { |e| expect(e.reason).to eq(:unknown_type) }
  end

  it "fails on a dangling model reference" do
    bundle = fixtures.bundle("A@default" => fixtures.model("A", [
                                                             { "name" => "x", "type" => fixtures.model_type("Gone@default") },
                                                           ]))

    expect { build(bundle) }
      .to raise_error(Lutaml::Model::Lml::RejectedError) { |e| expect(e.reason).to eq(:dangling_reference) }
  end

  it "refuses attribute keys it cannot materialize" do
    bundle = fixtures.bundle("A@default" => fixtures.model("A", [
                                                             { "name" => "x", "type" => fixtures.string_type, "discriminator" => {} },
                                                           ]))

    expect { build(bundle) }
      .to raise_error(Lutaml::Model::Lml::RejectedError, /discriminator/)
  end

  it "materializes a float attribute as the Float builtin with a binary64 default" do
    require_relative "../../support/lml_export_fixtures"
    bundle = Lutaml::Model::Lml.export_bundle(LmlExportFixtures::FloatAttr)
    classes = Lutaml::Model::Lml.import_bundle(bundle, namespace: Module.new)
    klass = classes.fetch("LmlExportFixtures::FloatAttr@default")
    expect(klass.attributes.values.map(&:type)).to all(eq(Lutaml::Model::Type::Float))
    expect(klass.attributes.values_at(:ratio, :tiny, :whole).map { |attribute| attribute.options[:default] })
      .to eq([0.71, 1.0e-05, 3.0])
    expect(klass.new.ratio).to eq(0.71)
    expect(Lutaml::Model::Lml.verify_materialization(bundle).checksum).to eq(bundle.checksum)
  end
end
