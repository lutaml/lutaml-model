# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_construction/models"

# custom_initialize: true marks a model whose application construction is
# hand-written. It is data in the bundle; the body is never serialized or run.
RSpec.describe "LML hand-written constructor marker" do
  let(:fx) { LmlConstructionFixtures }
  let(:lml) { Lutaml::Model::Lml }

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def doc_of(bundle, klass)
    bundle.models.fetch("#{klass.name}@default")
  end

  before { fx.ran.clear }

  describe "export" do
    it "marks a class-owned, an inherited and a module-owned custom initialize, and nothing else" do
      bundle = lml.export_bundle([fx::Money, fx::Euro, fx::Ledger, fx::Plain])

      expect(doc_of(bundle, fx::Money)["custom_initialize"]).to be(true)
      expect(doc_of(bundle, fx::Euro)["custom_initialize"]).to be(true)
      expect(doc_of(bundle, fx::Ledger)["custom_initialize"]).to be(true)
      expect(doc_of(bundle, fx::Plain)).not_to have_key("custom_initialize")
    end

    it "never runs or reads the constructor bodies" do
      lml.export_bundle([fx::Money, fx::Ledger])

      expect(fx.ran).to be_empty
    end

    it "keeps ordinary output unchanged: an unmarked graph carries no marker anywhere" do
      expect(lml.export_bundle(fx::Plain).canonical_json).not_to include("custom_initialize")
    end

    it "marks only the models that need it inside one graph" do
      bundle = lml.export_bundle(fx::Holder)

      expect(doc_of(bundle, fx::Money)["custom_initialize"]).to be(true)
      expect(doc_of(bundle, fx::Plain)).not_to have_key("custom_initialize")
      expect(doc_of(bundle, fx::Holder)).not_to have_key("custom_initialize")
    end

    it "passes the bundle validator and changes the checksum" do
      marked = lml.export_bundle(fx::Money)

      expect { Lutaml::Model::Lml::DocumentValidator.validate!(marked.to_h, kind: :bundle) }.not_to raise_error
      unmarked = Lutaml::Model::Lml::Bundle.new(
        roots: marked.roots, capabilities: marked.capabilities, value_types: {},
        models: marked.models.transform_values { |doc| doc.except("custom_initialize") }
      )
      expect(unmarked.checksum).not_to eq(marked.checksum)
    end

    it "keeps the legacy v1 export refusing a custom initialize by name" do
      error = refusal_of { lml.export(fx::Money) }

      expect(error.reason).to eq(:custom_initialize)
    end
  end

  describe "the shared fixture from the constructor targets" do
    let(:text) { File.read(File.expand_path("../../fixtures/lml_construction/marker_bundle.json", __dir__)) }

    it "loads and reproduces the checksum the TS loader measured" do
      bundle = Lutaml::Model::Lml::Importer.bundle(text)

      expect(bundle.checksum).to eq("sha256:20f766db12df617da2b7b5d621d771e7bb959b21052f44858591459d2195d188")
      expect(bundle.models["Example::Money@default"]["custom_initialize"]).to be(true)
      expect(bundle.models["Example::Plain@default"]).not_to have_key("custom_initialize")
    end
  end

  describe "malformed markers" do
    let(:base) { lml.export_bundle(fx::Money).to_h }

    [[false, "false"], [nil, "null"], ["true", "a string"], [1, "a number"], [{}, "an object"], [[true], "an array"]].each do |value, label|
      it "refuses #{label} as invalid_document at the marker location" do
        tree = Marshal.load(Marshal.dump(base))
        tree["models"].values.first["custom_initialize"] = value
        error = refusal_of { lml.import_bundle(tree) }

        expect(error.reason).to eq(:invalid_document)
        expect(error.location).to eq("/models/#{tree['models'].keys.first}/custom_initialize")
      end
    end
  end

  describe "import, stub and re-export" do
    let(:bundle) { lml.export_bundle(fx::Holder) }
    let(:holder) { stub_const("LmlConstructionImport", Module.new) }
    let(:classes) { lml.import_bundle(bundle, namespace: holder) }
    let(:money) { classes.fetch("#{fx::Money.name}@default") }

    it "re-exports the marker and the same checksum through the public API" do
      again = lml.verify_materialization(bundle)

      expect(again.checksum).to eq(bundle.checksum)
      expect(doc_of(again, fx::Money)["custom_initialize"]).to be(true)
    end

    it "exposes the marker on the fresh class only where the bundle says so" do
      plain = classes.fetch("#{fx::Plain.name}@default")

      expect(money.lml_custom_initialize?).to be(true)
      expect(plain).not_to respond_to(:lml_custom_initialize?)
    end

    it "fails by a named error when the application initializer is invoked without implementation" do
      error = refusal_of { money.construct(amount: 1) }

      expect(error.reason).to eq(:custom_initialize)
      expect(error.detail).to include("not implemented")
    end

    it "constructs through an explicit hand-written implementation and validates the result" do
      money.implement_initializer { |klass, amount, currency: "EUR"| klass.new(amount: amount, currency: currency) }
      built = money.construct(5, currency: "USD")

      expect([built.amount, built.currency]).to eq([5, "USD"])
      expect(refusal_of { money.implement_initializer { |_klass, *| Object.new }.construct }.detail).to include("returned Object")
    end

    it "keeps declared data construction and deserialization separate from the stub" do
      data = money.new(amount: 7, currency: "GBP")

      expect([data.amount, data.currency]).to eq([7, "GBP"])
      expect(money.from_json('{"amount": 9, "currency": "JPY"}').amount).to eq(9)
      expect(data.to_json).to eq('{"amount":7,"currency":"GBP"}')
    end

    it "does not carry the source body into the materialized class" do
      money.new(amount: 1)

      expect(fx.ran).to be_empty
    end

    it "refuses implement_initializer without a callable" do
      expect { money.implement_initializer }.to raise_error(ArgumentError, /callable/)
    end
  end
end
