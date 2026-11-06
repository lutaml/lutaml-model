# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1033: every builtin name the exporter can write must be a
# name the importer accepts (the LML builtin list is not allowed to drift
# from Lutaml::Model::Type's registry).
RSpec.describe "LML builtin type names" do
  let(:lml) { Lutaml::Model::Lml }
  let(:registry_names) { Lutaml::Model::Type::TYPE_CODES.keys.map(&:to_s) }
  # double is an alias of float: the exporter writes the first registered name.
  let(:emitted) { registry_names - ["double"] }

  def model_with(type)
    Class.new(Lutaml::Model::Serializable) do
      def self.name = "EveryBuiltin"
    end.tap { |klass| klass.attribute :x, type }
  end

  it "accepts every name the exporter writes for a registered builtin" do
    klass = Class.new(Lutaml::Model::Serializable) do
      def self.name = "EveryBuiltin"
    end
    registry_names.each { |type| klass.attribute :"a_#{type}", type.to_sym }

    bundle = lml.export_bundle(klass)
    written = bundle.to_h["models"].values.first["attributes"].map { |a| a["type"]["name"] }

    expect(written.uniq.sort).to eq(emitted.sort)
    expect(lml::DocumentValidator::BUILTIN_TYPES).to include(*emitted)
    imported = lml::Importer.bundle(bundle.canonical_json)
    expect(imported.to_h).to eq(bundle.to_h)
  end

  it "imports each registered builtin on its own" do
    emitted.each do |type|
      bundle = lml.export_bundle(model_with(type.to_sym))
      expect { lml::Importer.bundle(bundle.canonical_json) }.not_to raise_error, type
    end
  end

  it "still refuses double, which is never written" do
    expect(lml::DocumentValidator::BUILTIN_TYPES).not_to include("double")
  end
end
