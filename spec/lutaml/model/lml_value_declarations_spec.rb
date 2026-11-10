# frozen_string_literal: true

require "lutaml/model/lml"

module LmlValueDeclarationFixtures
  class Code < Lutaml::Model::Type::String
    VALUES = %w[a b].freeze

    def self.cast(value, options = {})
      return if value.nil?

      super(value, options.dup.tap { |copy| copy[:values] ||= VALUES })
    end
  end

  class QualifiedNamespace < Lutaml::Xml::Namespace
    uri "urn:declared-values"
    prefix_default "d"
    attribute_form_default :qualified
  end

  class QualifiedModel < Lutaml::Model::Serializable
    attribute :code, Code
    xml do
      root "qualified"
      namespace QualifiedNamespace
      map_attribute "code", to: :code
    end
  end

  class Model < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :code, Code, default: "a"
      attribute :other, :string
    end
    json do
      map "code", to: :code
      map "other", to: :other
    end
    xml do
      root "declared"
      map_element "code", to: :code
      map_element "other", to: :other
    end
  end
end

RSpec.describe Lutaml::Model::Lml::ValueDeclarations do
  let(:source) { LmlValueDeclarationFixtures::Model }
  let(:scalar) { LmlValueDeclarationFixtures::Code }
  let(:definition) { { "base" => "string", "facets" => { "enumeration" => %w[a b] } } }
  let(:registry) { described_class.new({ scalar => definition }) }
  let(:lml) { Lutaml::Model::Lml }

  it "keeps arbitrary named casters refused without explicit declarations" do
    expect { lml.export_bundle(source) }.to raise_error(lml::RejectedError) { |error| expect(error.reason).to eq(:unsupported_type) }
  end

  it "exports named identity, declared facets, defaults and choices without flattening" do
    tree = lml.export_bundle(source, value_declarations: registry).to_h
    id = "#{scalar.name}@default"
    expect(tree.fetch("value_types")).to eq(id => definition)
    model = tree.fetch("models").values.first
    expect(model.fetch("attributes").first.fetch("type")).to eq("kind" => "value", "id" => id)
    expect(model.fetch("attributes").first.fetch("default")).to eq("present" => true, "value" => "a")
    expect(model.fetch("choices").fetch("validation")).to eq("explicit")
    expect(lml::Importer.bundle(tree).to_h).to eq(tree)
  end

  it "requires native bindings and preserves their source reader and validation behavior" do
    bundle = lml.export_bundle(source, value_declarations: registry)
    expect { lml.import_bundle(bundle) }.to raise_error(lml::RejectedError) { |error| expect(error.reason).to eq(:missing_type_binding) }
    imported = lml.import_bundle(bundle, type_bindings: { "#{scalar.name}@default" => scalar }).fetch("#{source.name}@default")
    [{ code: "a" }, { code: "b" }, { code: "a", other: "x" }].each do |input|
      original = source.new(input)
      actual = imported.new(input)
      expect(actual.to_json).to eq(original.to_json)
      expect(actual.to_xml).to eq(original.to_xml)
      expect(actual.validate.map(&:class)).to eq(original.validate.map(&:class))
    end
    expect { imported.from_json('{"code":"unknown"}') }.to raise_error(Lutaml::Model::Type::InvalidValueError)
  end

  it "preserves qualified attribute namespaces while importing declared scalar models" do
    original_class = LmlValueDeclarationFixtures::QualifiedModel
    bundle = lml.export_bundle(original_class, value_declarations: registry)
    rule = bundle.models.values.first.fetch("mappings").fetch("xml").fetch("rules").first
    expect(rule.fetch("namespace")).to eq("mode" => "uri", "uri" => "urn:declared-values", "prefix" => "d")
    imported = lml.import_bundle(bundle, type_bindings: { "#{scalar.name}@default" => scalar }).fetch("#{original_class.name}@default")
    original = original_class.new(code: "a").to_xml(prefix: true)
    expect(imported.from_xml(original).to_xml(prefix: true)).to eq(original)
  end

  it "treats facet payloads as data rather than model references" do
    definition.fetch("facets")["opaque_payload"] = { "kind" => "model", "id" => "Missing@default" }
    tree = lml.export_bundle(source, value_declarations: registry).to_h
    expect(tree.fetch("models").keys).to eq(["#{source.name}@default"])
    expect(tree.fetch("value_types").values.first.fetch("facets").fetch("opaque_payload")).to eq("kind" => "model", "id" => "Missing@default")
  end

  it "uses exact source class identity rather than names or inherited behavior" do
    expect(registry.fetch(scalar.name)).to be_nil
    subclass = Class.new(scalar)
    stub_const("LmlUnregisteredCode", subclass)
    expect(registry.fetch(subclass)).to be_nil
    expect { described_class.new({ scalar.name => definition }) }.to raise_error(lml::RejectedError)
  end

  it "freezes a private data copy without freezing the caller's declarations" do
    item = described_class.new({ scalar => definition })
    definition.fetch("facets").fetch("enumeration") << "c"
    expect(item.fetch(scalar).fetch("facets").fetch("enumeration")).to eq(%w[a b])
    expect(item.fetch(scalar)).to be_frozen
    expect(item.to_h.fetch("version")).to eq(1)
  end

  it "refuses unsupported registry versions and executable metadata" do
    expect { described_class.new({ scalar => definition }, version: 2) }.to raise_error(lml::RejectedError) { |error| expect(error.reason).to eq(:unsupported_version) }
    invoked = false
    definition["facets"]["callback"] = -> { invoked = true }
    expect { described_class.new({ scalar => definition }) }.to raise_error(lml::RejectedError) { |error| expect(error.reason).to eq(:invalid_document) }
    expect(invoked).to be(false)
  end

  it "refuses unvalidated raw registries at the public exporter boundary" do
    expect { lml.export_bundle(source, value_declarations: { scalar => definition }) }.to raise_error(ArgumentError, /ValueDeclarations/)
  end
end
