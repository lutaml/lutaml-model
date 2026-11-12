# frozen_string_literal: true

require "lutaml/model"
require "date"

# Exporter-side findings of the final Ruby review of #1116 (H1, M3, M4, L4,
# L5, L6, L10): every construct the v2 contract cannot carry is refused by
# name at export, and everything carried is normalised to JSON scalars.
module LmlReviewExportFixtures # rubocop:disable Lint/ConstantDefinitionInBlock -- named fixtures: the document addresses models by class path
  class Item < Lutaml::Model::Serializable
    attribute :v, :string
  end

  class ItemList < Lutaml::Model::Collection
    instances :items, Item
  end

  class WithCollectionClass < Lutaml::Model::Serializable
    attribute :things, Item, collection: ItemList
  end

  class WithTransform < Lutaml::Model::Serializable
    attribute :x, :string, transform: { export: ->(v) { v.to_s.upcase } }
  end

  class WithPattern < Lutaml::Model::Serializable
    attribute :y, :string, pattern: /\Aab/
  end

  class WithModelChoice < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :a, :string
      attribute :b, :string
    end
  end

  class WithPolymorphic < Lutaml::Model::Serializable
    attribute :p, Item, polymorphic: [Item]
  end

  class WithMethod < Lutaml::Model::Serializable
    attribute :u, :string, method: :compute
  end

  class WithValidations < Lutaml::Model::Serializable
    attribute :t, :string, validations: { min: 3 }
  end

  class Target < Lutaml::Model::Serializable
    attribute :id, :string
  end

  class WithReference < Lutaml::Model::Serializable
    attribute :r, { ref: ["LmlReviewExportFixtures::Target", :id] }
  end

  class MyStr < Lutaml::Model::Type::String; end

  class WithValueType < Lutaml::Model::Serializable
    attribute :x, MyStr
  end

  class FloatOnInteger < Lutaml::Model::Serializable
    attribute :n, :integer, default: 1.5
  end

  class Scalars < Lutaml::Model::Serializable
    attribute :d, :date, default: Date.new(2020, 1, 2)
    attribute :s, :symbol, default: :foo
    attribute :c, :string, values: %i[a b]
    attribute :f, :float, default: 2
    attribute :h, :hash, default: { "a" => 1 }
  end

  class StringOnInteger < Lutaml::Model::Serializable
    attribute :n, :integer, default: "7"
  end

  class DataDefault < Lutaml::Model::Serializable
    attribute :opts, :hash, default: { "reference" => "Some.Thing", "kind" => "model", "id" => "X" }
  end

  class Plain < Lutaml::Model::Serializable
    attribute :a, :string
  end

  class SeqChoice < Lutaml::Model::Serializable
    attribute :a, :string
    attribute :b, :string
    xml do
      root "sc"
      sequence do
        map_element "a", to: :a
        choice(min: 1, max: 1) { map_element "b", to: :b }
      end
    end
  end

  class AnonColl < Lutaml::Model::Serializable
    attribute :things, Item,
              collection: Class.new(Lutaml::Model::Collection) { instances :items, LmlReviewExportFixtures::Item }
  end
end

RSpec.describe "LML exporter review fixes (#1116 final review)" do # rubocop:disable RSpec/DescribeClass
  let(:lml) { Lutaml::Model::Lml }
  let(:fx) { LmlReviewExportFixtures }

  def reason_of
    yield
    :exported
  rescue Lutaml::Model::Lml::RejectedError => e
    e.reason
  end

  def project(klass)
    Lutaml::Model::Lml::Exporter.project(klass)
  end

  describe "H1: behaviour the contract cannot carry is refused by name" do
    {
      "an attribute transform" => :WithTransform,
      "an attribute pattern" => :WithPattern,
      "a model-level choice block" => :WithModelChoice,
      "an attribute polymorphic list" => :WithPolymorphic,
      "a method-backed attribute" => :WithMethod,
      "attribute validations" => :WithValidations,
    }.each do |label, name|
      it "refuses #{label} in the document and the bundle (unsupported_mapping)" do
        klass = LmlReviewExportFixtures.const_get(name)
        expect(reason_of { project(klass) }).to eq(:unsupported_mapping)
        expect(reason_of { lml.export_bundle(klass) }).to eq(:unsupported_mapping)
      end
    end

    it "keeps the v1 document unchanged for such a model" do
      expect(reason_of { Lutaml::Model::Lml::Exporter.export(fx::WithPattern) }).to eq(:exported)
    end

    it "still exports the xml sequence choice compositor (its bounds travel in the mapping)" do
      expect(reason_of { project(fx::SeqChoice) }).to eq(:exported)
    end

    it "carries a nameable custom collection class as collection.class" do
      attribute = project(fx::WithCollectionClass).fetch("attributes").first
      expect(attribute.fetch("collection")).to eq("min" => 0, "max" => nil, "class" => fx::ItemList.name)
    end

    it "round-trips a custom collection class once the importer is given its binding" do
      bundle = lml.export_bundle(fx::WithCollectionClass)
      bindings = { fx::ItemList.name => fx::ItemList }
      expect(lml.verify_materialization(bundle, type_bindings: bindings).checksum).to eq(bundle.checksum)
    end

    it "refuses an anonymous custom collection class" do
      expect(reason_of { project(fx::AnonColl) }).to eq(:unsupported_mapping)
    end
  end

  describe "M3: defaults and enum values are JSON scalars the type can express" do
    let(:attributes) { project(fx::Scalars).fetch("attributes").to_h { |a| [a["name"], a] } }

    it "normalises Date, Symbol, enum symbols and an integer on a float to wire scalars" do
      expect(attributes.fetch("d").dig("default", "value")).to eq("2020-01-02")
      expect(attributes.fetch("s").dig("default", "value")).to eq("foo")
      expect(attributes.fetch("c").fetch("values")).to eq(%w[a b])
      expect(attributes.fetch("f").dig("default", "value")).to eq("2.0")
    end

    it "produces a bundle that imports and verifies from memory, not just from text" do
      bundle = lml.export_bundle(fx::Scalars)
      expect(lml.import_bundle(bundle)).to have_key("#{fx::Scalars.name}@default")
      expect(lml.verify_materialization(bundle).checksum).to eq(bundle.checksum)
    end

    it "refuses a float default on an integer attribute at export" do
      expect(reason_of { lml.export_bundle(fx::FloatOnInteger) }).to eq(:non_serializable_default)
    end

    it "refuses a string default on an integer attribute at export" do
      expect(reason_of { project(fx::StringOnInteger) }).to eq(:non_serializable_default)
    end
  end

  describe "M4: a custom value type cannot be exported" do
    it "is refused as unsupported_type (the exporter emits no value_types)" do
      expect(reason_of { project(fx::WithValueType) }).to eq(:unsupported_type)
      expect(reason_of { lml.export_bundle(fx::WithValueType) }).to eq(:unsupported_type)
    end
  end

  describe "L4: data values are never walked as references" do
    it "exports a hash default shaped like a model reference" do
      bundle = lml.export_bundle(fx::DataDefault)
      expect(bundle.models.keys).to eq(["#{fx::DataDefault.name}@default"])
    end
  end

  describe "L5: a reference attribute is refused as an unsupported type" do
    it "does not report a dangling reference" do
      expect(reason_of { lml.export_bundle(fx::WithReference) }).to eq(:unsupported_type)
    end
  end

  describe "L6: anonymous classes" do
    it "Exporter.project refuses an anonymous class instead of dropping the model key" do
      anon = Class.new(Lutaml::Model::Serializable) { attribute :a, :string }
      expect(reason_of { project(anon) }).to eq(:invalid_document)
    end
  end

  describe "L10: registers and substitution" do
    it "refuses an explicit register that is not registered" do
      expect(reason_of { lml.export_bundle(fx::Plain, register: "no_such_register") }).to eq(:invalid_document)
    end

    it "refuses a root pair whose register is not registered" do
      expect(reason_of { lml.export_bundle([[fx::Plain, "nosuch"]]) }).to eq(:invalid_document)
    end

    it "exports a root pair under a registered register" do
      Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:lml_review_pair))
      expect(lml.export_bundle([[fx::Plain, "lml_review_pair"]]).roots)
        .to eq(["#{fx::Plain.name}@lml_review_pair"])
    ensure
      Lutaml::Model::GlobalRegister.remove(:lml_review_pair)
    end

    it "exports under a registered register" do
      Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:lml_review_reg))
      expect(lml.export_bundle(fx::Plain, register: "lml_review_reg").roots)
        .to eq(["#{fx::Plain.name}@lml_review_reg"])
    ensure
      Lutaml::Model::GlobalRegister.remove(:lml_review_reg)
    end

    it "lets a failing register substitution propagate instead of silently using the original class" do
      Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:lml_review_sub))
      registered = Lutaml::Model::GlobalRegister.lookup(:lml_review_sub)
      allow(registered).to receive(:substitute).and_raise(RuntimeError, "substitution blew up")

      expect { Lutaml::Model::Lml::GraphExporter.default_resolver(fx::Plain.name, "lml_review_sub") }
        .to raise_error(RuntimeError, "substitution blew up")
    ensure
      Lutaml::Model::GlobalRegister.remove(:lml_review_sub)
    end
  end
end
