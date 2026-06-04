# frozen_string_literal: true

require "spec_helper"
require "lutaml/jsonld"
require "lutaml/yamlld"

RSpec.describe ":yamlld format registration" do
  it "is registered with FormatRegistry as an RDF format" do
    expect(Lutaml::Model::FormatRegistry.rdf_formats).to include(:yamlld)
  end

  it "uses Rdf::Mapping as the mapping class" do
    expect(Lutaml::Model::FormatRegistry.mappings_class_for(:yamlld))
      .to eq(Lutaml::Rdf::Mapping)
  end

  it "uses YamlLd::Adapter as the adapter class" do
    expect(Lutaml::Model::FormatRegistry.adapter_class_for(:yamlld))
      .to eq(Lutaml::YamlLd::Adapter)
  end

  it "shares LinkedDataTransform with :jsonld" do
    expect(Lutaml::Model::FormatRegistry.transformer_for(:yamlld))
      .to eq(Lutaml::Rdf::LinkedDataTransform)
    expect(Lutaml::Model::FormatRegistry.transformer_for(:yamlld))
      .to eq(Lutaml::Model::FormatRegistry.transformer_for(:jsonld))
  end

  it "declares Psych::SyntaxError as a parse error type" do
    expect(Lutaml::Model::FormatRegistry.error_types_for(:yamlld))
      .to include("Psych::SyntaxError")
  end
end
