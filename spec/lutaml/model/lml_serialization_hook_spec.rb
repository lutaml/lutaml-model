# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_serialization_hooks/models"

# Key-value rules may carry `custom: {to:, from:}` hook NAMES (never bodies).
# The importer makes real methods that fail by name until a hand-written
# implementation is installed through the public API.
RSpec.describe "LML serialization hooks" do
  let(:fx) { LmlSerializationHookFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:bundle) { lml.export_bundle(fx::Measure) }
  let(:holder) { stub_const("LmlHookHolder", Module.new) }
  let(:measure) { lml.import_bundle(bundle, namespace: holder).fetch("#{fx::Measure.name}@default") }

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def rules_of(bundle, klass, format = "json")
    bundle.models.fetch("#{klass.name}@default")["mappings"].fetch(format)["rules"].to_h { |r| [(r["key"] || r["name"]).first, r] }
  end

  before { fx.calls.clear }

  describe "export" do
    it "emits hook names and no `to` on hook-only rules; a normal rule keeps its `to`" do
      rules = rules_of(bundle, fx::Measure)

      expect(rules["category"]).to include("custom" => { "to" => "category_to_kv", "from" => "category_from_kv" })
      expect(rules["category"]).not_to have_key("to")
      expect(rules["amount"]).to include("to" => "amount")
      expect(rules["amount"]).not_to have_key("custom")
    end

    it "keeps every format's rules (json, yaml and toml) with their hooks" do
      %w[json yaml toml].each do |format|
        expect(rules_of(bundle, fx::Measure, format).values.count { |r| r["custom"] }).to eq(2)
      end
    end

    it "never calls, looks up or reads the source hook methods" do
      bundle
      lml.verify_materialization(bundle)

      expect(fx.calls).to be_empty
    end

    it "passes the bundle validator" do
      expect { Lutaml::Model::Lml::DocumentValidator.validate!(bundle.to_h, kind: :bundle) }.not_to raise_error
    end

    it "leaves a model without hooks exactly as before" do
      expect(lml.export_bundle(fx::Plain).canonical_json).not_to include("custom")
    end

    it "carries `with:` on an xml rule as hook names too (see lml_xml_serialization_hook_spec)" do
      rule = rules_of(lml.export_bundle(fx::XmlHook), fx::XmlHook, "xml").values.first

      expect(rule["custom"]).to eq("to" => "name_to_xml", "from" => "name_from_xml")
    end
  end

  describe "malformed hooks in a document" do
    def import_with(custom)
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      rule = tree["models"].values.first["mappings"]["json"]["rules"].find { |r| r["key"] == ["category"] }
      custom == :absent ? rule.delete("custom") : rule["custom"] = custom
      refusal_of { lml.import_bundle(tree, namespace: stub_const("LmlHookBad#{rand(10**9)}", Module.new)) }
    end

    [[[], "an array"], ["name", "a string"], [nil, "null"], [{}, "an empty object"],
     [{ "to" => "" }, "an empty name"], [{ "to" => 1 }, "a number name"], [{ "to" => "has space" }, "a bad identifier"],
     [{ "to" => "a", "from" => "a" }, "equal directions"], [{ "to" => "a", "extra" => "b" }, "an unknown key"],
     [{ "from" => "__lml_absent_to_x" }, "a reserved name"]].each do |value, label|
      it "refuses #{label} as invalid_document at the custom location" do
        error = import_with(value)

        expect(error.reason).to eq(:invalid_document)
        expect(error.location).to include("/custom")
      end
    end

    it "refuses a rule with neither `to` nor `custom`" do
      error = import_with(:absent)

      expect(error.reason).to eq(:unsupported_mapping)
    end

    it "refuses `custom` on an xml any_attribute rule" do
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      tree["models"].values.first["mappings"]["xml"] = { "root" => { "element" => "m" },
                                                         "rules" => [{ "kind" => "any_attribute", "to" => "amount", "custom" => { "to" => "a" } }] }
      tree["capabilities"] = (tree["capabilities"] + ["xml"]).sort
      error = refusal_of { lml.import_bundle(tree) }

      expect(error.reason).to eq(:unsupported_mapping)
    end

    it "refuses a hook name used as both a to and a from hook" do
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      rules = tree["models"].values.first["mappings"]["json"]["rules"]
      rules.find { |r| r["key"] == ["note"] }["custom"] = { "from" => "category_to_kv" }
      error = refusal_of { lml.import_bundle(tree, namespace: stub_const("LmlHookMixed", Module.new)) }

      expect(error.reason).to eq(:unsupported_mapping)
      expect(error.detail).to include("both")
    end
  end

  describe "materialization" do
    it "re-exports the same checksum with hooks and hook-only rules intact" do
      again = lml.verify_materialization(bundle)

      expect(again.checksum).to eq(bundle.checksum)
      expect(rules_of(again, fx::Measure)["note"]["custom"]).to eq("to" => "note_to_kv", "from" => "note_from_kv")
    end

    it "keeps a one-direction hook one-directional on re-export" do
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      %w[json yaml toml].each do |format|
        rules = tree["models"].values.first["mappings"][format]["rules"]
        rules.find { |r| r["key"] == ["note"] }["custom"] = { "to" => "note_to_kv" }
      end
      one_way = Lutaml::Model::Lml::Importer.bundle(tree)
      again = lml.verify_materialization(one_way)

      expect(rules_of(again, fx::Measure)["note"]["custom"]).to eq("to" => "note_to_kv")
      expect(again.checksum).to eq(one_way.checksum)
    end

    it "declares real methods for each named hook" do
      expect(measure.lml_serialization_hooks).to include("category_to_kv" => :to, "category_from_kv" => :from)
      expect(measure.instance_methods).to include(:category_to_kv, :note_from_kv)
    end
  end

  describe "stubs fail by name until implemented" do
    it "fails a write with custom_serialization naming the hook" do
      error = refusal_of { measure.new(amount: 1).to_json }

      expect(error.reason).to eq(:custom_serialization)
      expect(error.detail).to include("write hook").and include("category_to_kv").and include("not implemented")
    end

    it "fails a read with custom_serialization naming the hook" do
      error = refusal_of { measure.from_json('{"amount":1,"category":"x"}') }

      expect(error.reason).to eq(:custom_serialization)
      expect(error.detail).to include("read hook").and include("category_from_kv")
    end

    it "builds declared data without running any hook" do
      built = measure.new(amount: 3, category: "c", note: "n")

      expect([built.amount, built.category, built.note]).to eq([3, "c", "n"])
    end

    it "fails a one-direction rule only for the direction it does not declare" do
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      %w[json yaml toml].each do |format|
        rules = tree["models"].values.first["mappings"][format]["rules"]
        rules.find { |r| r["key"] == ["note"] }["custom"] = { "to" => "note_to_kv" }
      end
      klass = lml.import_bundle(tree, namespace: stub_const("LmlHookOneWay", Module.new)).values.first
      klass.implement_serialization("category_to_kv") { |_m, doc| doc["category"] = "x" }
      klass.implement_serialization("category_from_kv") { |m, value| m.category = value }
      klass.implement_serialization("note_to_kv") { |m, doc| doc["note"] = m.note }

      expect(klass.new(amount: 1, note: "n").to_json).to include('"note":"n"')
      error = refusal_of { klass.from_json('{"amount":1,"note":"n"}') }
      expect(error.reason).to eq(:custom_serialization)
      expect(error.detail).to include("declares no read hook")
    end
  end

  describe "explicit hand-written implementations (public API)" do
    before do
      measure.implement_serialization(
        "category_to_kv" => ->(model, doc) { doc["category"] = model.category&.upcase },
        "category_from_kv" => ->(model, value) { model.category = value&.downcase },
        "note_to_kv" => ->(model, doc) { doc["note"] = model.note && "note:#{model.note}" },
        "note_from_kv" => ->(model, value) { model.note = value&.delete_prefix("note:") },
      )
    end

    it "writes through the installed hooks" do
      json = measure.new(amount: 2, category: "abc", note: "z").to_json

      expect(JSON.parse(json)).to eq("amount" => 2, "category" => "ABC", "note" => "note:z")
    end

    it "reads through the installed hooks" do
      read = measure.from_json('{"amount":4,"category":"XYZ","note":"note:q"}')

      expect([read.amount, read.category, read.note]).to eq([4, "xyz", "q"])
    end

    it "does not change the declared checksum" do
      expect(lml.verify_materialization(bundle).checksum).to eq(bundle.checksum)
    end

    it "refuses an unknown hook name, a reserved name and a non-callable" do
      expect(refusal_of { measure.implement_serialization("ghost") { nil } }.reason).to eq(:custom_serialization)
      expect(refusal_of { measure.implement_serialization("__lml_absent_from_x") { nil } }.reason).to eq(:custom_serialization)
      expect { measure.implement_serialization("category_to_kv", 5) }.to raise_error(ArgumentError, /callable/)
    end
  end
end
