# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_value_type_export/models"

RSpec.describe "LML explicit named value-type export" do
  let(:fx) { LmlValueTypeExportFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:registry) do
    {
      "Slug" => { class: fx::SlugType, base: "string",
                  facets: { "pattern" => "[a-z]+", "min_length" => 1 } },
      "Count" => { class: fx::CountType, base: "integer",
                   facets: { "min_inclusive" => 0 } },
    }
  end

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def attribute_of(bundle, model, name)
    bundle.models.fetch("#{fx.name}::#{model}@default")["attributes"].find { |a| a["name"] == name }
  end

  describe "without a registry (old behavior preserved)" do
    it "refuses a custom value type by name" do
      error = refusal_of { lml.export_bundle(fx::Account) }

      expect(error.reason).to eq(:unsupported_type)
      expect(error.detail).to include("SlugType")
    end

    it "refuses it when the registry is empty" do
      expect(refusal_of { lml.export_bundle(fx::Account, value_types: {}) }.reason).to eq(:unsupported_type)
    end
  end

  describe "with a registered type" do
    let(:bundle) { lml.export_bundle(fx::Ledger, value_types: registry) }

    it "declares each used type once with its base and facets" do
      expect(bundle.value_types).to eq(
        "Count" => { "base" => "integer", "facets" => { "min_inclusive" => 0 } },
        "Slug" => { "base" => "string", "facets" => { "min_length" => 1, "pattern" => "[a-z]+" } },
      )
    end

    it "types attributes as named value types, never as the base builtin" do
      expect(attribute_of(bundle, "Account", "slug")["type"]).to eq("kind" => "value", "id" => "Slug")
      expect(attribute_of(bundle, "Account", "tags")["type"]).to eq("kind" => "value", "id" => "Slug")
      expect(attribute_of(bundle, "Account", "limit")["type"]).to eq("kind" => "value", "id" => "Count")
      expect(attribute_of(bundle, "Account", "label")["type"]).to eq("kind" => "builtin", "name" => "string")
    end

    it "exports typed defaults under the base" do
      expect(attribute_of(bundle, "Account", "slug")["default"]).to eq("present" => true, "value" => "x")
      expect(attribute_of(bundle, "Account", "limit")["default"]).to eq("present" => true, "value" => 7)
    end

    it "passes the existing bundle validator" do
      expect { Lutaml::Model::Lml::DocumentValidator.validate!(bundle.to_h, kind: :bundle) }.not_to raise_error
    end

    it "does not leave value_types inside the model documents" do
      expect(bundle.models.values.map(&:keys).flatten).not_to include("value_types")
    end

    it "declares only the types a graph uses" do
      only = lml.export_bundle(fx::Plain, value_types: registry)

      expect(only.value_types).to eq({})
    end
  end

  describe "import with trusted bindings and re-export" do
    let(:bindings) { { "Slug" => fx::SlugType, "Count" => fx::CountType } }
    let(:bundle) { lml.export_bundle(fx::Ledger, value_types: registry) }
    let(:holder) { stub_const("LmlValueTypeRoundTrip", Module.new) }

    def reexport(classes, bundle)
      models = classes.each_with_object({}) { |(id, klass), map| map[klass] = map[klass.name] = id.rpartition("@").first }
      names = ->(klass) { models.fetch(klass) { klass.is_a?(String) ? klass : klass.name } }
      value_types = bundle.value_types.to_h do |id, definition|
        [id, { class: bindings.fetch(id), base: definition["base"], facets: definition["facets"] }]
      end
      generated = Lutaml::Model::Lml::GraphExporter.export(
        bundle.roots.map { |id| [classes.fetch(id), id.rpartition("@").last] },
        projector: Lutaml::Model::Lml::Exporter.graph_projector(names: names, value_types: value_types),
        resolver: ->(model, register) { classes["#{model}@#{register}"] }, names: names
      )
      Lutaml::Model::Lml::Bundle.new(**generated.to_h.transform_keys(&:to_sym)
                                       .slice(:roots, :models, :value_types, :capabilities))
    end

    it "re-exports identical declarations and checksum" do
      classes = lml.import_bundle(bundle, namespace: holder, type_bindings: bindings)
      again = reexport(classes, bundle)

      expect(again.value_types).to eq(bundle.value_types)
      expect(again.checksum).to eq(bundle.checksum)
    end

    it "refuses import without bindings, naming the missing ID" do
      error = refusal_of { lml.import_bundle(bundle, namespace: holder) }

      expect(error.reason).to eq(:missing_type_binding)
      expect(error.detail).to match(/Slug|Count/)
    end

    it "refuses import when only some IDs are bound, naming the unbound one" do
      error = refusal_of do
        lml.import_bundle(bundle, namespace: holder, type_bindings: { "Slug" => fx::SlugType })
      end

      expect(error.reason).to eq(:missing_type_binding)
      expect(error.detail).to include("Count")
    end
  end

  describe "registry validation" do
    def export_with(value_types)
      refusal_of { lml.export_bundle(fx::Account, value_types: value_types) }
    end

    def entry(**changes)
      { class: fx::SlugType, base: "string", facets: {} }.merge(changes)
    end

    it "refuses one class registered under two IDs as ambiguous" do
      error = export_with("A" => entry, "B" => entry)

      expect(error.reason).to eq(:invalid_document)
      expect(error.detail).to include("ambiguous")
    end

    it "refuses an ID declared as both a string and a symbol" do
      error = export_with("A" => entry, A: entry(class: fx::CountType, base: "integer"))

      expect(error.detail).to include("declared twice")
    end

    it "refuses a builtin type class (no silent aliasing)" do
      error = export_with("S" => entry(class: Lutaml::Model::Type::String))

      expect(error.detail).to include("builtin type")
    end

    it "refuses a non-Value class, a non-class and an anonymous class" do
      expect(export_with("S" => entry(class: String)).detail).to include("Type::Value")
      expect(export_with("S" => entry(class: "SlugType")).detail).to include("Type::Value")
      expect(export_with("S" => entry(class: Class.new(Lutaml::Model::Type::Value))).detail).to include("unnamed")
    end

    it "refuses invalid IDs" do
      expect(export_with("has space" => entry).reason).to eq(:invalid_document)
      expect(export_with("" => entry).reason).to eq(:invalid_document)
    end

    it "refuses unknown and unsupported bases" do
      expect(export_with("S" => entry(base: "nope")).reason).to eq(:unknown_type)
      expect(export_with("S" => entry(base: "double")).reason).to eq(:unsupported_type)
      expect(export_with("S" => entry(base: nil)).reason).to eq(:unknown_type)
    end

    it "refuses unknown facets and invalid facet values" do
      expect(export_with("S" => entry(facets: { "bogus" => 1 })).reason).to eq(:unsupported_type)
      expect(export_with("S" => entry(facets: { "min_length" => -1 })).reason).to eq(:invalid_document)
      expect(export_with("S" => entry(facets: { "min_length" => 2.5 })).reason).to eq(:invalid_document)
      expect(export_with("S" => entry(facets: { "pattern" => "" })).reason).to eq(:invalid_document)
      expect(export_with("S" => entry(facets: { "white_space" => "squash" })).reason).to eq(:invalid_document)
      expect(export_with("S" => entry(facets: { "min_inclusive" => 1.5 })).reason).to eq(:invalid_document)
    end

    it "refuses inconsistent facet bounds" do
      error = export_with("S" => entry(facets: { "min_length" => 5, "max_length" => 2 }))

      expect(error.detail).to include("exceeds")
    end

    it "refuses unknown entry keys and a malformed registry" do
      expect(export_with("S" => entry(coerce: true)).detail).to include("unknown key")
      expect(export_with("S" => "string").reason).to eq(:invalid_document)
      expect(export_with(%w[S]).reason).to eq(:invalid_document)
    end

    it "accepts string-keyed entries and decimal-text bounds" do
      bundle = lml.export_bundle(fx::Priced, value_types: {
                                   "Amount" => { "class" => fx::AmountType, "base" => "decimal",
                                                 "facets" => { "max_inclusive" => "9.50", "fraction_digits" => 2 } },
                                 })

      expect(bundle.value_types["Amount"]).to eq("base" => "decimal",
                                                 "facets" => { "fraction_digits" => 2, "max_inclusive" => "9.50" })
      expect(attribute_of(bundle, "Priced", "amount")["default"]).to eq("present" => true, "value" => "9.50")
    end
  end

  describe "classes outside the registry" do
    it "still refuses an unregistered custom type when another is registered" do
      only_slug = { "Slug" => registry["Slug"] }
      error = refusal_of { lml.export_bundle(fx::Account, value_types: only_slug) }

      expect(error.reason).to eq(:unsupported_type)
      expect(error.detail).to include("CountType")
    end

    it "does not match a subclass of a registered class" do
      error = refusal_of { lml.export_bundle(fx::Subclassed, value_types: registry) }

      expect(error.reason).to eq(:unsupported_type)
      expect(error.detail).to include("OtherSlugType")
    end
  end

  describe "defaults stay validated" do
    it "still refuses a Proc default instead of evaluating it" do
      error = refusal_of { lml.export_bundle(fx::ProcDefault, value_types: registry) }

      expect(error.reason).to eq(:lambda_default)
    end

    it "refuses a default that does not fit the declared base" do
      error = refusal_of { lml.export_bundle(fx::BadDefault, value_types: registry) }

      expect(error.reason).to eq(:non_serializable_default)
      expect(error.detail).to include("integer")
    end
  end

  describe "defaults against facets" do
    def faceted(**facets)
      lml.export_bundle(fx::Faceted, value_types: {
                          "Slug" => { class: fx::SlugType, base: "string", facets: facets.fetch(:slug, {}) },
                          "Count" => { class: fx::CountType, base: "integer", facets: facets.fetch(:count, {}) },
                        })
    end

    it "accepts defaults inside their facets" do
      bundle = faceted(slug: { "pattern" => "[A-Z]+", "max_length" => 3 }, count: { "min_inclusive" => 5, "max_exclusive" => 6 })

      expect(bundle.value_types.keys).to eq(%w[Count Slug])
    end

    it "refuses a default that breaks a pattern, length or bound" do
      expect(refusal_of { faceted(slug: { "pattern" => "[a-z]+" }) }.detail).to include("pattern")
      expect(refusal_of { faceted(slug: { "min_length" => 4 }) }.detail).to include("min_length")
      expect(refusal_of { faceted(count: { "max_inclusive" => 4 }) }.reason).to eq(:non_serializable_default)
      expect(refusal_of { faceted(count: { "min_exclusive" => 5 }) }.detail).to include("min_exclusive")
    end

    it "refuses a facet pattern that does not compile" do
      error = refusal_of { faceted(slug: { "pattern" => "(" }) }

      expect(error.reason).to eq(:invalid_document)
    end
  end

  describe "builtin exports are unchanged" do
    it "exports identical bundles with and without a registry" do
      plain = lml.export_bundle(fx::Plain)
      registered = lml.export_bundle(fx::Plain, value_types: registry)

      expect(registered.canonical_json).to eq(plain.canonical_json)
      expect(plain.value_types).to eq({})
    end

    it "keeps the v1 export free of value types" do
      document = lml.export(fx::Plain)

      expect(document.canonical_json).not_to include("value_types")
    end
  end
end
