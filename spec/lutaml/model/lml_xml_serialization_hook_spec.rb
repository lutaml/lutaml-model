# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_xml_hooks/models"

# `custom: {to:, from:}` hook names also travel on XML content, element and
# attribute rules; the importer rebuilds failing stubs with the serializer's
# own call signatures and the public API installs handwritten implementations.
RSpec.describe "LML XML serialization hooks" do
  let(:fx) { LmlXmlHookFixtures }
  let(:lml) { Lutaml::Model::Lml }

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def export(klass)
    lml.export_bundle(klass)
  end

  def rules_of(bundle, klass)
    bundle.models.fetch("#{klass.name}@default")["mappings"]["xml"]["rules"]
  end

  def fresh(klass)
    holder = stub_const("LmlXmlHookHolder#{rand(10**9)}", Module.new)
    lml.import_bundle(export(klass), namespace: holder).fetch("#{klass.name}@default")
  end

  def caused_by_named_failure?(error)
    chain = [error, (error.cause if error.respond_to?(:cause))].compact
    chain.any? { |e| e.is_a?(Lutaml::Model::Lml::RejectedError) && e.reason == :custom_serialization }
  end

  before { fx.calls.clear }

  describe "export" do
    let(:rules) { rules_of(export(fx::SymbolLike), fx::SymbolLike) }

    it "keeps the content rule with its `to` target and carries the hook names" do
      content = rules.find { |r| r["kind"] == "content" }

      expect(content).to include("to" => "content", "custom" => { "to" => "content_to_xml", "from" => "content_from_xml" })
    end

    it "leaves the ordinary attribute rule and a hook-free model unchanged" do
      expect(rules.find { |r| r["kind"] == "attribute" }).not_to have_key("custom")
      expect(export(fx::Regular).canonical_json).not_to include("custom")
    end

    it "carries named element hooks, keeps `to`, and lets a hook-only element omit it" do
      named = rules_of(export(fx::Mixed), fx::Mixed)

      expect(named.find { |r| r["name"] == ["title"] }).to include("to" => "title", "custom" => { "to" => "title_to_xml", "from" => "title_from_xml" })
      expect(named.find { |r| r["name"] == ["extra"] }).to include("custom" => { "to" => "extra_to_xml", "from" => "extra_from_xml" })
      expect(named.find { |r| r["name"] == ["extra"] }).not_to have_key("to")
    end

    it "never calls the source callbacks, on export or on the reconstruction gate" do
      lml.verify_materialization(export(fx::SymbolLike))
      lml.verify_materialization(export(fx::Mixed))

      expect(fx.calls).to be_empty
    end

    it "keeps refusing an order driven by an executable callback" do
      error = refusal_of { export(fx::CallbackOrdered) }

      expect(error.reason).to eq(:imperative_element_order)
    end

    it "no longer lets the legacy v1 export drop a callback silently" do
      error = refusal_of { lml.export(fx::SymbolLike) }

      expect(error.reason).to eq(:unsupported_mapping)
      expect(error.detail).to include("content")
      expect(refusal_of { lml.export(fx::Regular) }).to be_nil
    end
  end

  describe "malformed XML hooks in a document" do
    let(:bundle) { export(fx::SymbolLike) }

    def import_with
      tree = Marshal.load(Marshal.dump(bundle.to_h))
      rule = tree["models"].values.first["mappings"]["xml"]["rules"].find { |r| r["kind"] == "content" }
      yield rule
      refusal_of { lml.import_bundle(tree, namespace: stub_const("LmlXmlHookBad#{rand(10**9)}", Module.new)) }
    end

    [[[], "an array"], [{}, "an empty object"], [{ "to" => "" }, "an empty name"], [{ "to" => "x y" }, "a bad identifier"],
     [{ "to" => "a", "from" => "a" }, "equal directions"], [{ "to" => "a", "x" => "b" }, "an unknown key"]].each do |value, label|
      it "refuses #{label} as invalid_document" do
        error = import_with { |rule| rule["custom"] = value }

        expect(error.reason).to eq(:invalid_document)
        expect(error.location).to end_with("/custom").or include("/custom/")
      end
    end

    it "refuses custom on an any_attribute rule" do
      error = import_with do |rule|
        rule.replace("kind" => "any_attribute", "to" => "type", "custom" => { "to" => "x" })
      end

      expect(error.reason).to eq(:unsupported_mapping)
    end

    it "refuses a name shared by an xml rule and a key-value rule (different signatures)" do
      tree = Marshal.load(Marshal.dump(export(fx::KvAndXml).to_h))

      error = refusal_of { lml.import_bundle(tree, namespace: stub_const("LmlXmlHookKv", Module.new)) }
      expect(error.reason).to eq(:unsupported_mapping)
      expect(error.detail).to include("xml and key-value")
    end
  end

  describe "fresh import" do
    it "re-exports the same checksum with the hooks intact" do
      bundle = export(fx::SymbolLike)
      again = lml.verify_materialization(bundle)

      expect(again.checksum).to eq(bundle.checksum)
      expect(rules_of(again, fx::SymbolLike).find { |r| r["kind"] == "content" }["custom"]).to eq("to" => "content_to_xml", "from" => "content_from_xml")
    end

    it "declares the stubs with the serializer's call signatures" do
      klass = fresh(fx::SymbolLike)

      expect(klass.lml_serialization_hook_kinds).to eq("content_to_xml" => :xml, "content_from_xml" => :xml)
      expect(klass.instance_method(:content_to_xml).arity).to eq(3)
      expect(klass.instance_method(:content_from_xml).arity).to eq(2)
      expect(fresh(fx::Mixed).instance_method(:extra_to_xml).arity).to eq(3)
    end

    it "fails a write by name when no handwritten implementation is installed" do
      error = begin
        fresh(fx::SymbolLike).new(type: "HTML", content: "<i>m</i>").to_xml
      rescue StandardError => e
        e
      end

      expect(caused_by_named_failure?(error)).to be(true)
      expect(error.message + error.cause.to_s).to include("content_to_xml")
    end

    it "fails a read by name on the attempted direction" do
      klass = fresh(fx::SymbolLike)
      klass.implement_serialization("content_to_xml") { |_m, _parent, _doc| nil }
      error = begin
        klass.from_xml('<UnitSymbol xmlns="urn:lml:xmlhooks" type="HTML">m</UnitSymbol>')
      rescue StandardError => e
        e
      end

      expect(caused_by_named_failure?(error)).to be(true)
      expect(error.message + error.cause.to_s).to include("content_from_xml")
    end

    it "keeps ordinary xml output identical, with no hook involved" do
      klass = fresh(fx::Regular)
      source = fx::Regular.new(name: "n", tag: "t")

      expect(klass.new(name: "n", tag: "t").to_xml).to eq(source.to_xml)
    end

    it "writes raw markup through an explicit handwritten handler, as the source does" do
      klass = fresh(fx::SymbolLike)
      invoked = false
      klass.implement_serialization("content_to_xml") do |model, parent, doc|
        invoked = true
        doc.add_xml_fragment(parent, model.content)
      end
      source = fx::SymbolLike.new(type: "HTML", content: "<i>m</i>").to_xml
      fx.calls.clear

      expect(klass.new(type: "HTML", content: "<i>m</i>").to_xml).to eq(source)
      expect(invoked).to be(true)
      expect(fx.calls).to be_empty
    end

    it "passes the handler (model, parent, doc) and the read handler (model, value)" do
      klass = fresh(fx::SymbolLike)
      seen = {}
      klass.implement_serialization(
        "content_to_xml" => ->(model, parent, doc) { seen[:write] = [model.class, !parent.nil?, !doc.nil?] },
        "content_from_xml" => ->(model, value) { 
          seen[:read] = [model.class, value]
          model.content = value
        },
      )
      klass.new(type: "t", content: "c").to_xml
      read = klass.from_xml('<UnitSymbol xmlns="urn:lml:xmlhooks" type="t">hello</UnitSymbol>')

      expect(seen[:write]).to eq([klass, true, true])
      expect(seen[:read]).to eq([klass, "hello"])
      expect(read.content).to eq("hello")
    end

    it "does not run the source callbacks when the fresh class serializes" do
      klass = fresh(fx::Mixed)
      klass.implement_serialization("title_to_xml" => ->(*) {}, "extra_to_xml" => ->(*) {})
      klass.new(title: "t").to_xml

      expect(fx.calls).to be_empty
    end
  end
end
