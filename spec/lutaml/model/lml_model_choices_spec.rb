# frozen_string_literal: true

require "lutaml/model/lml"
require_relative "../../support/lml_model_choices_fixtures"

RSpec.describe Lutaml::Model::Lml do
  let(:fixtures) { LmlModelChoicesFixtures }

  def copy(tree)
    JSON.parse(JSON.generate(tree))
  end

  LmlModelChoicesFixtures::CASES.each do |name, cases|
    cases.each_with_index do |input, index|
      it "preserves #{name} choice validation and deferred I/O for case #{index}" do
        source = LmlModelChoicesFixtures.const_get(name)
        bundle = described_class.export_bundle(source)
        imported = described_class.import_bundle(bundle).fetch("#{source.name}@default")
        original = source.new(input)
        actual = imported.new(input)
        expected = original.validate.map(&:class)
        expect(actual.validate.map(&:class)).to eq(expected)
        expect(actual.to_json).to eq(original.to_json)
        source_read = begin
          source.from_json(JSON.generate(input)).validate.map(&:class)
        rescue Lutaml::Model::CollectionCountOutOfRangeError => e
          e.class
        end
        imported_read = begin
          imported.from_json(JSON.generate(input)).validate.map(&:class)
        rescue Lutaml::Model::CollectionCountOutOfRangeError => e
          e.class
        end
        expect(imported_read).to eq(source_read)
      end
    end
  end

  it "carries nested groups, their XML render policy scope and exact bounds" do
    document = described_class.export_bundle(fixtures::Nested).to_h.fetch("models").values.first
    choices = document.fetch("choices")
    expect(choices.values_at("version", "validation")).to eq([1, "explicit"])
    root = choices.fetch("groups").first
    expect(root.values_at("min", "max", "format")).to eq([1, 1, "xml"])
    expect(root.fetch("members").first.fetch("choice").fetch("members")).to eq([
                                                                                 { "attribute" => "a" }, { "attribute" => "b" }
                                                                               ])
  end

  it "requires the explicit choice capability" do
    tree = copy(described_class.export_bundle(fixtures::Plain).to_h)
    tree["capabilities"].delete("model.choices.v1")
    expect { described_class.import_bundle(tree) }.to raise_error(described_class::RejectedError) { |error| expect(error.reason).to eq(:capability_missing) }
  end

  it "refuses unknown metadata versions and validation phases" do
    tree = copy(described_class.export_bundle(fixtures::Plain).to_h)
    metadata = tree.fetch("models").values.first.fetch("choices")
    metadata["version"] = 2
    expect { described_class.import_bundle(tree) }.to raise_error(described_class::RejectedError) { |error| expect(error.reason).to eq(:unsupported_version) }
    metadata["version"] = 1
    metadata["validation"] = "constructor"
    expect { described_class.import_bundle(tree) }.to raise_error(described_class::RejectedError) { |error| expect(error.reason).to eq(:invalid_document) }
  end

  it "refuses dangling or ambiguous member references" do
    tree = copy(described_class.export_bundle(fixtures::Plain).to_h)
    member = tree.fetch("models").values.first.fetch("choices").fetch("groups").first.fetch("members").first
    member["attribute"] = "missing"
    expect { described_class.import_bundle(tree) }.to raise_error(described_class::RejectedError) { |error| expect(error.reason).to eq(:dangling_reference) }
    member["attribute"] = "a"
    member["choice"] = {}
    expect { described_class.import_bundle(tree) }.to raise_error(described_class::RejectedError) { |error| expect(error.reason).to eq(:invalid_document) }
  end

  it "covers choices in canonical identity without adding metadata to ordinary models" do
    original = described_class.export_bundle(fixtures::Plain)
    tree = copy(original.to_h)
    tree.fetch("models").values.first.fetch("choices").fetch("groups").first["min"] = 0
    expect(described_class::Importer.bundle(tree).checksum).not_to eq(original.checksum)
    plain = Class.new(Lutaml::Model::Serializable)
    stub_const("LmlNoChoiceSnapshot", plain)
    plain.attribute(:value, :string)
    ordinary = described_class.export_bundle(plain).to_h
    expect(ordinary.fetch("models").values.first).not_to have_key("choices")
    expect(ordinary.fetch("capabilities")).not_to include("model.choices.v1")
  end
end
