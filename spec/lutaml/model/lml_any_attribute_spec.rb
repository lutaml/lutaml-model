# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../support/lml_any_attribute_fixtures"

# lutaml-model#1033 card 02g: the XML catch-all attribute mapping
# (map_all_attributes) is carried as {kind:"any_attribute", to:<attr>}.
RSpec.describe "LML any_attribute rule" do
  let(:lml) { Lutaml::Model::Lml }
  let(:fx) { LmlAnyAttributeFixtures }
  let(:rejected) { lml::RejectedError }
  let(:document) { lml::Exporter.project(fx::Tag) }
  let(:rules) { document.dig("mappings", "xml", "rules") }

  def refusal
    yield
    nil
  rescue rejected => e
    e
  end

  def validate(hash)
    Lutaml::Model::Lml::DocumentValidator.validate!(hash, kind: :document)
  end

  def with_rules(extra, attributes: nil)
    copy = JSON.parse(JSON.generate(document))
    copy["attributes"] = attributes if attributes
    copy["mappings"]["xml"]["rules"] = extra
    copy
  end

  it "exports the catch-all as the last rule, naming the hash attribute" do
    expect(rules.last).to eq("kind" => "any_attribute", "to" => "other_attributes")
    expect(rules.map { |r| r["kind"] }).to eq(%w[attribute any_attribute])
  end

  it "leaves the v1 export unchanged" do
    expect(lml.export(fx::Tag).to_h.dig("mappings", "xml", "rules").map { |r| r["kind"] }).to eq(%w[attribute])
  end

  it "validates the exported document and the schema lists the kind" do
    expect(refusal { validate(document) }).to be_nil
    schema = JSON.parse(File.read(File.expand_path("../../../schema/lml/document.schema.json", __dir__)))
    expect(schema.dig("$defs", "rule", "properties", "kind", "enum")).to include("any_attribute")
  end

  it "refuses a second any_attribute rule by name" do
    two = with_rules(rules + [{ "kind" => "any_attribute", "to" => "other_attributes" }])
    expect(refusal { validate(two) }.reason).to eq(:unsupported_mapping)
  end

  it "refuses a target that is not a declared attribute" do
    bad = with_rules([{ "kind" => "any_attribute", "to" => "nope" }])
    expect(refusal { validate(bad) }.reason).to eq(:dangling_reference)
  end

  it "refuses a target that is not a hash attribute" do
    bad = with_rules([{ "kind" => "any_attribute", "to" => "id" }])
    expect(refusal { validate(bad) }.reason).to eq(:unsupported_mapping)
  end

  it "refuses extra keys on the rule" do
    bad = with_rules([{ "kind" => "any_attribute", "to" => "other_attributes", "name" => ["x"] }])
    expect(refusal { validate(bad) }.reason).to eq(:unsupported_mapping)
  end

  it "refuses map_all_attributes matching: instead of dropping the filter" do
    error = refusal { lml::Exporter.project(fx::Filtered) }
    expect(error.reason).to eq(:unsupported_mapping)
    expect(error.message).to include("map_all_attributes matching:")
  end

  describe "round trip in a rebuilt model" do
    let(:bundle) { lml.export_bundle(fx::Tag) }
    let(:xml) { '<tag xmlns:x="urn:u" id="1" x:a="2" b="3"/>' }

    it "verifies the materialization and reproduces catch-all behaviour" do
      expect(lml.verify_materialization(bundle).checksum).to eq(bundle.checksum)

      classes = lml.import_bundle(bundle, namespace: stub_const("LmlAnyAttrImported", Module.new))
      imported = classes.fetch("LmlAnyAttributeFixtures::Tag@default")
      parsed = imported.from_xml(xml)
      expect(parsed.id).to eq("1")
      # Pinned Ruby behaviour: the prefix is dropped, only the local name is kept.
      expect(parsed.other_attributes).to eq("a" => "2", "b" => "3")
      expect(parsed.to_xml).to eq(fx::Tag.from_xml(xml).to_xml)
    end
  end
end
