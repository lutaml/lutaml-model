# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_default_binding/models"

# Trusted declarative constants for opaque (Proc) defaults: the issue's
# declarative equivalent, never an automatic translation of the Proc.
RSpec.describe "LML default bindings" do
  let(:fx) { LmlDefaultBindingFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:subject_id) { "#{fx::Subject.name}@default" }
  let(:types) do
    lml::ValueDeclarations.new({
                                 fx::CodeType => { "base" => "string",
                                                   "facets" => { "pattern" => "[a-z]+", "max_length" => 3 } },
                               })
  end
  let(:constants) do
    { "lang" => "en", "flag" => false, "note" => nil, "tags" => [], "ratio" => 0.25, "code" => "abc" }
  end

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def export(bindings)
    lml.export_bundle(fx::Subject, value_declarations: types, default_bindings: bindings)
  end

  def attribute_of(bundle, name, model = fx::Subject)
    bundle.models.fetch("#{model.name}@default")["attributes"].find { |a| a["name"] == name }
  end

  before { fx.executed.clear }

  describe "without a binding (old behavior)" do
    it "still refuses the Proc default by name" do
      error = refusal_of { lml.export_bundle(fx::Subject, value_declarations: types) }

      expect(error.reason).to eq(:lambda_default)
    end

    it "keeps the v1 export refusing it" do
      expect(refusal_of { lml.export(fx::Subject) }&.reason).to be_a(Symbol)
    end

    it "never calls the Proc to find out" do
      refusal_of { lml.export_bundle(fx::Subject, value_declarations: types) }

      expect(fx.executed).to be_empty
    end
  end

  describe "with bindings" do
    let(:bundle) { export({ subject_id => constants }) }

    it "exports each constant as the declared default and keeps false, null and empty" do
      expect(attribute_of(bundle, "lang")["default"]).to eq("present" => true, "value" => "en")
      expect(attribute_of(bundle, "flag")["default"]).to eq("present" => true, "value" => false)
      expect(attribute_of(bundle, "note")["default"]).to eq("present" => true, "value" => nil)
      expect(attribute_of(bundle, "tags")["default"]).to eq("present" => true, "value" => [])
      expect(attribute_of(bundle, "ratio")["default"]).to eq("present" => true, "value" => "0.25")
      expect(attribute_of(bundle, "code")["default"]).to eq("present" => true, "value" => "abc")
    end

    it "leaves declared constants and undefaulted attributes as they were" do
      expect(attribute_of(bundle, "fixed")["default"]).to eq("present" => true, "value" => "kept")
      expect(attribute_of(bundle, "bare")["default"]).to eq("present" => false)
    end

    it "never executes, reads or mutates the Proc defaults" do
      before_defaults = fx::Subject.attributes.transform_values { |a| a.options[:default] }
      bundle

      expect(fx.executed).to be_empty
      expect(fx::Subject.attributes.transform_values { |a| a.options[:default] }).to eq(before_defaults)
    end

    it "passes the bundle validator" do
      expect { Lutaml::Model::Lml::DocumentValidator.validate!(bundle.to_h, kind: :bundle) }.not_to raise_error
    end

    it "accepts symbol attribute names and works through a graph" do
      graph = lml.export_bundle(fx::Parent, value_declarations: types,
                                            default_bindings: { subject_id => constants.transform_keys(&:to_sym) })

      expect(attribute_of(graph, "lang")["default"]["value"]).to eq("en")
    end
  end

  describe "reconstruction" do
    let(:bundle) { export(subject_id => constants) }
    let(:bindings) { { "#{fx::CodeType.name}@default" => fx::CodeType } }

    it "imports the constants as ordinary declared defaults and re-exports an equal checksum" do
      holder = stub_const("LmlDefaultBindingHolder", Module.new)
      again = lml.verify_materialization(bundle, namespace: holder, type_bindings: bindings)

      expect(again.checksum).to eq(bundle.checksum)
      classes = lml.import_bundle(bundle, namespace: stub_const("LmlDefaultBindingHolderTwo", Module.new),
                                          type_bindings: bindings)
      fresh = classes.fetch(subject_id).new

      expect([fresh.lang, fresh.flag, fresh.note, fresh.ratio]).to eq(["en", false, nil, 0.25])
    end
  end

  describe "invalid bindings" do
    it "refuses a binding that targets a declared constant default" do
      error = refusal_of { export(subject_id => constants.merge("fixed" => "other")) }

      expect(error.reason).to eq(:invalid_document)
      expect(error.detail).to include("declared constant default")
    end

    it "refuses a binding that targets an attribute with no default" do
      expect(refusal_of { export(subject_id => constants.merge("bare" => "x")) }.detail).to include("no default")
    end

    it "refuses an unknown attribute, an unknown model and an unexported model by name" do
      expect(refusal_of { export(subject_id => constants.merge("ghost" => 1)) }.detail).to include("ghost")
      expect(refusal_of { export(subject_id => constants, "Nope@default" => { "x" => 1 }) }.detail).to include("matched no")
    end

    it "refuses malformed binding tables" do
      expect(refusal_of { export("not-an-id" => { "lang" => "en" }) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(subject_id => {}) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(subject_id => "en") }.reason).to eq(:invalid_document)
      expect(refusal_of { export(%w[x]) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(subject_id => { "lang" => "en", lang: "fr" }) }.detail).to include("twice")
    end

    it "refuses a constant that does not fit the attribute's type" do
      error = refusal_of { export(subject_id => constants.merge("flag" => "yes")) }

      expect(error.reason).to eq(:non_serializable_default)
    end

    it "refuses a constant with no portable form (a Proc, an object)" do
      expect(refusal_of { export(subject_id => constants.merge("lang" => -> { "en" })) }.reason).to eq(:non_serializable_default)
      expect(refusal_of { export(subject_id => constants.merge("lang" => Object.new)) }.reason).to eq(:non_serializable_default)
    end

    it "refuses a constant that breaks the registered type's facets" do
      expect(refusal_of { export(subject_id => constants.merge("code" => "ABC")) }.detail).to include("pattern")
      expect(refusal_of { export(subject_id => constants.merge("code" => "abcd")) }.detail).to include("max_length")
    end

    it "still refuses a Proc default that has no binding when others do" do
      error = refusal_of { export(subject_id => constants.except("lang")) }

      expect(error.reason).to eq(:lambda_default)
      expect(error.detail).to include("lang")
    end
  end
end
