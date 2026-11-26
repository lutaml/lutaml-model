# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_value_type_export/models"

RSpec.describe "LML named value-type export through ValueDeclarations" do
  let(:fx) { LmlValueTypeExportFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:declarations) { lml::ValueDeclarations }
  let(:slug_id) { "#{fx.name}::SlugType@default" }
  let(:count_id) { "#{fx.name}::CountType@default" }
  let(:registry) do
    declarations.new({
                       fx::SlugType => { "base" => "string", "facets" => { "pattern" => "[a-z]+", "min_length" => 1 } },
                       fx::CountType => { "base" => "integer", "facets" => { "min_inclusive" => 0 } },
                     })
  end

  # A one-class registry; the bundle ID derives from the class name.
  def declare(klass, base, facets = {})
    declarations.new({ klass => { "base" => base, "facets" => facets.transform_keys(&:to_s) } })
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
      expect(refusal_of { lml.export_bundle(fx::Account, value_declarations: declarations.new({})) }.reason)
        .to eq(:unsupported_type)
    end
  end

  describe "with a registered type" do
    let(:bundle) { lml.export_bundle(fx::Ledger, value_declarations: registry) }

    it "declares each used type once with its base and facets" do
      expect(bundle.value_types).to eq(
        count_id => { "base" => "integer", "facets" => { "min_inclusive" => 0 } },
        slug_id => { "base" => "string", "facets" => { "min_length" => 1, "pattern" => "[a-z]+" } },
      )
    end

    it "types attributes as named value types, never as the base builtin" do
      expect(attribute_of(bundle, "Account", "slug")["type"]).to eq("kind" => "value", "id" => slug_id)
      expect(attribute_of(bundle, "Account", "tags")["type"]).to eq("kind" => "value", "id" => slug_id)
      expect(attribute_of(bundle, "Account", "limit")["type"]).to eq("kind" => "value", "id" => count_id)
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
      only = lml.export_bundle(fx::Plain, value_declarations: registry)

      expect(only.value_types).to eq({})
    end
  end

  describe "import with trusted bindings and re-export" do
    let(:bindings) { { slug_id => fx::SlugType, count_id => fx::CountType } }
    let(:bundle) { lml.export_bundle(fx::Ledger, value_declarations: registry) }
    let(:holder) { stub_const("LmlValueTypeRoundTrip", Module.new) }

    it "re-exports identical declarations and checksum through the public verify_materialization" do
      again = lml.verify_materialization(bundle, namespace: holder, type_bindings: bindings)

      expect(again.value_types).to eq(bundle.value_types)
      expect(again.checksum).to eq(bundle.checksum)
      expect(again).to eq(bundle)
    end

    it "verifies without a namespace and from the bundle's JSON text" do
      again = lml.verify_materialization(bundle.to_json, type_bindings: bindings)

      expect(again.checksum).to eq(bundle.checksum)
    end

    it "refuses verification without bindings, naming the missing ID" do
      error = refusal_of { lml.verify_materialization(bundle, namespace: holder) }

      expect(error.reason).to eq(:missing_type_binding)
    end

    it "refuses import without bindings, naming the missing ID" do
      error = refusal_of { lml.import_bundle(bundle, namespace: holder) }

      expect(error.reason).to eq(:missing_type_binding)
      expect(error.detail).to match(/SlugType|CountType/)
    end

    it "imports with bindings and exposes the registered classes on the generated attributes" do
      classes = lml.import_bundle(bundle, namespace: holder, type_bindings: bindings)

      expect(classes.fetch("#{fx.name}::Account@default").attributes[:slug].type).to eq(fx::SlugType)
    end

    it "refuses import when only some IDs are bound, naming the unbound one" do
      error = refusal_of do
        lml.import_bundle(bundle, namespace: holder, type_bindings: { slug_id => fx::SlugType })
      end

      expect(error.reason).to eq(:missing_type_binding)
      expect(error.detail).to include("CountType")
    end
  end

  describe "declaration validation" do
    def export_with(entries)
      refusal_of { lml.export_bundle(fx::Account, value_declarations: declarations.new(entries)) }
    end

    def entry(**changes)
      { "base" => "string", "facets" => {} }.merge(changes.transform_keys(&:to_s))
    end

    it "refuses a builtin type class (no silent aliasing)" do
      error = export_with(Lutaml::Model::Type::String => entry)

      expect(error.reason).to eq(:unsupported_type)
      expect(error.detail).to include("builtin type")
    end

    it "refuses a non-Value class, a non-class and an anonymous class" do
      [String, "SlugType", Class.new(Lutaml::Model::Type::Value)].each do |key|
        expect(export_with(key => entry).reason).to eq(:unsupported_type)
      end
    end

    it "refuses unknown and unsupported bases" do
      expect(export_with(fx::SlugType => entry(base: "nope")).reason).to eq(:unknown_type)
      expect(export_with(fx::SlugType => entry(base: "double")).reason).to eq(:unsupported_type)
      expect(export_with(fx::SlugType => entry(base: nil)).reason).to be_a(Symbol)
    end

    it "carries unknown facets as data and refuses invalid values of known facets" do
      expect { declarations.new({ fx::SlugType => entry(facets: { "bogus" => 1 }) }) }.not_to raise_error
      [{ "min_length" => -1 }, { "min_length" => 2.5 }, { "pattern" => "" },
       { "white_space" => "squash" }, { "min_inclusive" => 1.5 }].each do |facets|
        expect(export_with(fx::SlugType => entry(facets: facets)).reason).to eq(:invalid_document)
      end
    end

    it "refuses inconsistent facet bounds" do
      error = export_with(fx::SlugType => entry(facets: { "min_length" => 5, "max_length" => 2 }))

      expect(error).to be_a(Lutaml::Model::Lml::RejectedError)
    end

    it "refuses unknown entry keys and a malformed registry" do
      expect(export_with(fx::SlugType => entry(coerce: true))).to be_a(Lutaml::Model::Lml::RejectedError)
      expect(export_with(fx::SlugType => "string").reason).to eq(:invalid_document)
      expect(refusal_of { declarations.new(%w[S]) }.reason).to eq(:invalid_document)
    end

    it "accepts decimal-text bounds" do
      bundle = lml.export_bundle(fx::Priced, value_declarations: declare(
        fx::AmountType, "decimal", "max_inclusive" => "9.50", "fraction_digits" => 2
      ))
      id = "#{fx.name}::AmountType@default"

      expect(bundle.value_types[id]).to eq("base" => "decimal",
                                           "facets" => { "fraction_digits" => 2, "max_inclusive" => "9.50" })
      expect(attribute_of(bundle, "Priced", "amount")["default"]).to eq("present" => true, "value" => "9.50")
    end
  end

  describe "classes outside the registry" do
    it "still refuses an unregistered custom type when another is registered" do
      only_slug = declare(fx::SlugType, "string")
      error = refusal_of { lml.export_bundle(fx::Account, value_declarations: only_slug) }

      expect(error.reason).to eq(:unsupported_type)
      expect(error.detail).to include("CountType")
    end

    it "does not match a subclass of a registered class" do
      error = refusal_of { lml.export_bundle(fx::Subclassed, value_declarations: registry) }

      expect(error.reason).to eq(:unsupported_type)
      expect(error.detail).to include("OtherSlugType")
    end
  end

  describe "defaults stay validated" do
    it "still refuses a Proc default instead of evaluating it" do
      error = refusal_of { lml.export_bundle(fx::ProcDefault, value_declarations: registry) }

      expect(error.reason).to eq(:lambda_default)
    end

    it "refuses a default that does not fit the declared base" do
      error = refusal_of { lml.export_bundle(fx::BadDefault, value_declarations: registry) }

      expect(error.reason).to eq(:non_serializable_default)
      expect(error.detail).to include("integer")
    end
  end

  describe "standalone documents" do
    it "rejects a registry that is not a ValueDeclarations" do
      expect { Lutaml::Model::Lml::Exporter.project(fx::Account, value_declarations: {}) }
        .to raise_error(ArgumentError, /ValueDeclarations/)
    end

    it "keeps refusing a custom type in a standalone document" do
      expect(refusal_of { Lutaml::Model::Lml::Exporter.project(fx::Account) }.reason).to eq(:unsupported_type)
    end
  end

  describe "digit facets" do
    def priced(value, **facets)
      klass = Class.new(Lutaml::Model::Serializable)
      stub_const("LmlDigitModel#{value.to_s.hash.abs}", klass)
      klass.attribute :amount, fx::AmountType, default: value
      klass.json { map "amount", to: :amount }
      lml.export_bundle(klass, value_declarations: declare(fx::AmountType, "decimal", facets))
    end

    it "keeps defaults exactly on the total and fraction limits" do
      expect(priced("123.45", total_digits: 5, fraction_digits: 2).value_types.fetch("#{fx.name}::AmountType@default")["facets"])
        .to eq("fraction_digits" => 2, "total_digits" => 5)
      expect(priced("-0.05", total_digits: 2, fraction_digits: 2)).to be_a(Lutaml::Model::Lml::Bundle)
      expect(priced("9.50", total_digits: 2, fraction_digits: 1)).to be_a(Lutaml::Model::Lml::Bundle)
      expect(priced("0", total_digits: 1, fraction_digits: 0)).to be_a(Lutaml::Model::Lml::Bundle)
      expect(priced("007.0", total_digits: 1, fraction_digits: 0)).to be_a(Lutaml::Model::Lml::Bundle)
    end

    it "refuses defaults one digit over either limit" do
      over_total = refusal_of { priced("1234.5", total_digits: 4) }
      over_fraction = refusal_of { priced("1.234", fraction_digits: 2) }

      expect(over_total.reason).to eq(:non_serializable_default)
      expect(over_total.detail).to include("total_digits 4")
      expect(over_fraction.detail).to include("fraction_digits 2")
    end

    it "counts exactly, with no float rounding, for very long decimals" do
      long = "1#{'0' * 30}.#{'0' * 29}1"

      expect(priced(long, total_digits: 61, fraction_digits: 30)).to be_a(Lutaml::Model::Lml::Bundle)
      expect(refusal_of { priced(long, total_digits: 60) }.reason).to eq(:non_serializable_default)
    end

    it "does not apply numeric facets to a string base" do
      klass = Class.new(Lutaml::Model::Serializable)
      stub_const("LmlDigitStringModel", klass)
      klass.attribute :amount, fx::AmountType, default: "12345"
      klass.json { map "amount", to: :amount }
      bundle = lml.export_bundle(klass, value_declarations: declare(fx::AmountType, "string",
                                                           "max_inclusive" => 5, "total_digits" => 2))

      expect(bundle.value_types.fetch("#{fx.name}::AmountType@default")["base"]).to eq("string")
    end
  end

  describe "float defaults against bounds" do
    def floated(value, **facets)
      klass = Class.new(Lutaml::Model::Serializable)
      stub_const("LmlFloatModel#{value.to_s.hash.abs}", klass)
      klass.attribute :reading, fx::FloatBound, default: value
      klass.json { map "reading", to: :reading }
      lml.export_bundle(klass, value_declarations: declare(fx::FloatBound, "float", facets))
    end

    it "refuses the reported default below min_inclusive" do
      error = refusal_of do
        lml.export_bundle(fx::FloatRecord,
                            value_declarations: declare(fx::FloatBound, "float", "min_inclusive" => 3))
      end

      expect(error.reason).to eq(:non_serializable_default)
      expect(error.detail).to include("2.0 breaks min_inclusive 3")
    end

    it "keeps defaults exactly on inclusive bounds and inside exclusive ones" do
      bundle = floated(3.0, min_inclusive: 3, max_inclusive: "3.0", min_exclusive: "2.99", max_exclusive: 4)

      expect(bundle.models.values.first["attributes"].first["default"]).to eq("present" => true, "value" => "3.0")
    end

    it "refuses defaults on or past exclusive bounds and past inclusive ones" do
      expect(refusal_of { floated(3.0, min_exclusive: 3) }.detail).to include("min_exclusive")
      expect(refusal_of { floated(3.0, max_exclusive: "3.0") }.detail).to include("max_exclusive")
      expect(refusal_of { floated(3.5, max_inclusive: 3) }.detail).to include("max_inclusive")
    end

    it "compares exponent wire forms exactly" do
      expect(floated(1.0e-5, min_inclusive: "0.00001")).to be_a(Lutaml::Model::Lml::Bundle)
      expect(refusal_of { floated(1.0e-5, min_inclusive: "0.000011") }.reason).to eq(:non_serializable_default)
      expect(floated(1.0e20, max_inclusive: "100000000000000000000")).to be_a(Lutaml::Model::Lml::Bundle)
      expect(refusal_of { floated(1.0e20, max_exclusive: "100000000000000000000") }.reason).to eq(:non_serializable_default)
    end

    it "compares the shortest wire decimal, not binary approximations" do
      expect(floated(0.1, min_inclusive: "0.1", max_inclusive: "0.1")).to be_a(Lutaml::Model::Lml::Bundle)
      expect(refusal_of { floated(0.1, min_exclusive: "0.1") }.reason).to eq(:non_serializable_default)
    end

    it "preserves unbounded float types and negative values" do
      expect(floated(-2.5)).to be_a(Lutaml::Model::Lml::Bundle)
      expect(floated(-2.5, min_inclusive: -3, max_inclusive: -2)).to be_a(Lutaml::Model::Lml::Bundle)
      expect(refusal_of { floated(-2.5, min_inclusive: -2) }.reason).to eq(:non_serializable_default)
    end

    it "still checks float patterns by wire text" do
      expect(refusal_of { floated(2.0, pattern: "3.*") }.detail).to include("pattern")
    end
  end

  describe "defaults against facets" do
    def faceted(**facets)
      lml.export_bundle(fx::Faceted, value_declarations: declarations.new({
                                                                            fx::SlugType => { "base" => "string", "facets" => facets.fetch(:slug, {}) },
                                                                            fx::CountType => { "base" => "integer", "facets" => facets.fetch(:count, {}) },
                                                                          }))
    end

    it "accepts defaults inside their facets" do
      bundle = faceted(slug: { "pattern" => "[A-Z]+", "max_length" => 3 }, count: { "min_inclusive" => 5, "max_exclusive" => 6 })

      expect(bundle.value_types.keys).to eq([count_id, slug_id])
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
      registered = lml.export_bundle(fx::Plain, value_declarations: registry)

      expect(registered.canonical_json).to eq(plain.canonical_json)
      expect(plain.value_types).to eq({})
    end

    it "keeps the v1 export free of value types" do
      document = lml.export(fx::Plain)

      expect(document.canonical_json).not_to include("value_types")
    end
  end
end
