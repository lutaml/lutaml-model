# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_effective_namespace/models"

# A rule-level `uri` namespace (xml:id) is reconstructable when the bound
# attribute type declares exactly that namespace; otherwise it is refused.
RSpec.describe "LML type-level rule namespaces on import" do
  let(:fx) { LmlEffectiveNamespaceFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:registry) do
    { "xml:id" => { class: Lutaml::Xml::W3c::XmlIdType, base: "string", facets: {} },
      "other" => { class: fx::OtherNsType, base: "string", facets: {} } }
  end
  let(:bindings) { { "xml:id" => Lutaml::Xml::W3c::XmlIdType, "other" => fx::OtherNsType } }
  let(:bundle) { lml.export_bundle(fx::Host, value_types: registry) }

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def tampered
    tree = Marshal.load(Marshal.dump(bundle.to_h))
    rules = tree["models"].fetch("#{fx::Host.name}@default")["mappings"]["xml"]["rules"]
    yield rules.find { |r| r["name"] == ["id"] }["namespace"]
    tree
  end

  it "re-exports the same checksum through the public API with the types bound" do
    again = lml.verify_materialization(bundle, type_bindings: bindings)

    expect(again.checksum).to eq(bundle.checksum)
  end

  it "refuses a uri the bound type does not declare, by name" do
    error = refusal_of { lml.import_bundle(tampered { |ns| ns["uri"] = "urn:elsewhere" }, type_bindings: bindings) }

    expect(error.reason).to eq(:unsupported_mapping)
    expect(error.detail).to include("not declared by the type")
  end

  it "refuses a prefix that differs from the type's" do
    error = refusal_of { lml.import_bundle(tampered { |ns| ns["prefix"] = "zz" }, type_bindings: bindings) }

    expect(error.reason).to eq(:unsupported_mapping)
  end

  it "refuses a uri on an attribute whose type declares no namespace" do
    tree = Marshal.load(Marshal.dump(bundle.to_h))
    rules = tree["models"].fetch("#{fx::Host.name}@default")["mappings"]["xml"]["rules"]
    rules.find { |r| r["name"] == ["plainAttribute"] }["namespace"] = { "mode" => "uri", "uri" => "urn:lml:other", "prefix" => "o" }

    expect(refusal_of { lml.import_bundle(tree, type_bindings: bindings) }.reason).to eq(:unsupported_mapping)
  end

  it "still refuses a missing binding by name before reaching the namespace" do
    expect(refusal_of { lml.import_bundle(bundle) }.reason).to eq(:missing_type_binding)
  end
end
