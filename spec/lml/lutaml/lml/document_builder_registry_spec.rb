# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"

RSpec.describe Lutaml::Lml::DocumentBuilder, "DEFAULT_REGISTRY" do
  let(:registry) { described_class::DEFAULT_REGISTRY }

  it "is a Hash" do
    expect(registry).to be_a(Hash)
  end

  it "is frozen" do
    expect(registry).to be_frozen
  end

  it "maps all builder keys to LML model classes" do
    aggregate_failures do
      expect(registry[:document]).to eq(Lutaml::Lml::Document)
      expect(registry[:package]).to eq(Lutaml::Lml::Package)
      expect(registry[:class]).to eq(Lutaml::Lml::UmlClass)
      expect(registry[:enum]).to eq(Lutaml::Lml::Enum)
      expect(registry[:data_type]).to eq(Lutaml::Lml::DataType)
      expect(registry[:diagram]).to eq(Lutaml::Lml::Diagram)
      expect(registry[:attribute]).to eq(Lutaml::Lml::TopElementAttribute)
      expect(registry[:cardinality]).to eq(Lutaml::Lml::Cardinality)
      expect(registry[:association]).to eq(Lutaml::Lml::Association)
      expect(registry[:operation]).to eq(Lutaml::Lml::Operation)
      expect(registry[:constraint]).to eq(Lutaml::Lml::Constraint)
      expect(registry[:value]).to eq(Lutaml::Lml::Value)
      expect(registry[:view_import]).to eq(Lutaml::Lml::ViewImport)
      expect(registry[:view_filter]).to eq(Lutaml::Lml::ViewFilter)
    end
  end

  it "uses itself as the default constructor argument" do
    builder = described_class.new
    expect(builder.registry).to eq(registry)
  end

  it "accepts a custom registry" do
    custom = { document: Lutaml::Lml::Document }
    builder = described_class.new(custom)
    expect(builder.registry).to eq(custom)
  end

  describe "LmlConverter is no longer defined (regression guard)" do
    it "is not present in the Lml namespace" do
      expect(Lutaml::Lml.constants).not_to include(:LmlConverter)
    end
  end
end
