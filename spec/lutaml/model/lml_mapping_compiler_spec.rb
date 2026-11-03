# frozen_string_literal: true

require "spec_helper"
require "json"
require "yaml"
require "lutaml/model/lml/mapping_compiler"
require "lutaml/model/lml/ordered_content"
require_relative "../../support/lml_mapping_fixtures"

# lutaml-model#1033 card 03b: rebuild Ruby mapping policies from a
# neutral bundle.
RSpec.describe Lutaml::Model::Lml::MappingCompiler do
  let(:fx) { LmlMappingFixtures }
  let(:exporter) { Lutaml::Model::Lml::Exporter }
  let(:rejected) { Lutaml::Model::Lml::RejectedError }
  let(:holder) { stub_const("LmlMapGen", Module.new) }

  def compile(bundle, into: holder)
    classes = fx.fresh_classes(bundle, into)
    described_class.apply(classes, bundle)
    classes
  end

  def refusal(bundle, into: holder)
    compile(bundle, into: into)
    nil
  rescue rejected => e
    e
  end

  # A bundle with one hand-edited model document.
  def edited(source = fx::Doc)
    bundle = Marshal.load(Marshal.dump(fx.bundle_for(source, fx::Item, fx::Entry)))
    yield bundle["models"]["#{source.name}@default"]["mappings"]
    bundle
  end

  describe "restoring exported policies" do
    let(:bundle) { fx.bundle_for(fx::Doc, fx::Item, fx::Entry) }
    let(:classes) { compile(bundle) }
    let(:doc) { classes["LmlMappingFixtures::Doc@default"] }

    it "exports fresh mappings identical to the source models (xml/json/yaml)" do
      classes.each do |id, klass|
        expect(exporter.project(klass).fetch("mappings")).to eq(bundle["models"][id]["mappings"]), id
      end
    end

    it "serializes like the source in every format" do
      attrs = { title: "T", count: 3, note: "", kind: "b",
                items: [{ id: "i", label: "<x>" }], entries: [{ name: "n", value: "v" }] }
      source = fx::Doc.new(attrs.merge(items: [fx::Item.new(id: "i", label: "<x>")],
                                       entries: [fx::Entry.new(name: "n", value: "v")]))
      fresh = doc.new(attrs.merge(items: [classes["LmlMappingFixtures::Item@default"].new(id: "i", label: "<x>")],
                                  entries: [classes["LmlMappingFixtures::Entry@default"].new(name: "n", value: "v")]))

      expect(fresh.to_xml).to eq(source.to_xml)
      expect(fresh.to_json).to eq(source.to_json)
      expect(fresh.to_yaml).to eq(source.to_yaml)
      expect(fresh.to_xml).to include('xmlns="urn:lml-map:a"', "<![CDATA[<x>]]>")
    end

    it "restores child_mappings on a key-value rule" do
      with = fx.with_child_mappings(bundle)
      klass = compile(with)["LmlMappingFixtures::Doc@default"]
      entries = klass.mappings_for(:json).mappings.find { |r| r.to == :entries }
      expect(entries.child_mappings).to eq(name: :key, value: :value)
      expect(klass.new(count: 1, entries: [klass.attributes[:entries].type(nil).new(name: "n", value: "v")]).to_json)
        .to include('"entries":{"n":"v"}')
    end

    it "parses documents the source parses" do
      xml = fx::Doc.new(title: "t", count: 1, note: "n").to_xml
      expect(doc.from_xml(xml).to_xml).to eq(xml)
      json = fx::Doc.new(title: "t", count: 1, entries: [fx::Entry.new(name: "a", value: "b")]).to_json
      expect(doc.from_json(json).to_json).to eq(fx::Doc.from_json(json).to_json)
    end

    it "does not touch the source classes" do
      classes
      expect(fx::Doc.mappings_for(:xml).root_element).to eq("doc")
      expect(doc).not_to equal(fx::Doc)
      expect(classes.values).to all(satisfy { |k| k.name.start_with?("LmlMapGen::") })
    end

    it "gives equal namespaces one class and restores the prefix" do
      xml = doc.mappings_for(:xml)
      expect([xml.namespace_uri, xml.namespace_prefix]).to eq(["urn:lml-map:a", "m"])
    end

    it "declares nothing for formats the bundle omits" do
      bundle = edited { |m| m.delete("yaml") }
      expect(compile(bundle)["LmlMappingFixtures::Doc@default"].mappings.keys).to contain_exactly(:xml, :json)
    end
  end

  describe "render and namespace policy" do
    it "restores the resolved nil/empty/default of each rule" do
      doc = compile(fx.bundle_for(fx::Doc, fx::Item, fx::Entry))["LmlMappingFixtures::Doc@default"]
      by_name = doc.mappings_for(:xml).mappings.to_h { |r| [Array(r.name).first, r] }
      expect(by_name["note"].value_map(:to)).to include(nil: :omitted, empty: :blank)
      expect(by_name["note"].render_default).to be(true)
      expect(by_name["title"].value_map(:to)).to include(nil: :blank)
      expect(by_name["kind"].value_map(:to)).to include(nil: :nil)
    end

    it "treats unqualified as the explicit opt-out" do
      bundle = edited { |m| m["xml"]["rules"][0]["namespace"] = { "mode" => "unqualified" } }
      rule = compile(bundle)["LmlMappingFixtures::Doc@default"].mappings_for(:xml).mappings.first
      expect(rule.namespace_set?).to be(true)
      expect(rule.namespace).to be_nil
    end

    it "restores an unqualified model namespace" do
      bundle = edited { |m| m["xml"]["namespace"] = { "mode" => "unqualified" } }
      expect(compile(bundle)["LmlMappingFixtures::Doc@default"].mappings_for(:xml).namespace_param).to eq(:blank)
    end

    it "refuses a rule-level namespace uri, which the Ruby DSL cannot express" do
      bundle = edited { |m| m["xml"]["rules"][0]["namespace"] = { "mode" => "uri", "uri" => "urn:other" } }
      expect(refusal(bundle)).to have_attributes(reason: :unsupported_mapping, model_id: "LmlMappingFixtures::Doc@default")
    end
  end

  describe "ordered content" do
    let(:para) { LmlOrderFixtures::Para }
    let(:ids) { LmlOrderFixtures.constants }
    let(:bundle) { fx.bundle_for(para, LmlOrderFixtures::Emphasis) }
    let(:classes) { compile(bundle) }
    let(:fresh) { classes["LmlOrderFixtures::Para@default"] }

    def descriptor(klass)
      Lutaml::Model::Lml::OrderedContent.descriptor_for(klass, mapping: klass.mappings_for(:xml))
    end

    it "rebuilds mixed mappings that capture the same tokens as the source" do
      xml = LmlOrderFixtures::PARA_XML
      expect(fresh.mappings_for(:xml)).to be_mixed_content
      tokens = Lutaml::Model::Lml::OrderedContent.capture(descriptor(fresh), fresh.from_xml(xml))
      expect(tokens).to eq(Lutaml::Model::Lml::OrderedContent.capture(descriptor(para), para.from_xml(xml)))
    end

    it "applies tokens to a rebuilt instance and serializes in token order" do
      xml = LmlOrderFixtures::PARA_XML
      tokens = Lutaml::Model::Lml::OrderedContent.capture(descriptor(para), para.from_xml(xml))
      parsed = fresh.from_xml(xml)
      target = fresh.new(fresh.attributes.keys.to_h { |k| [k, parsed.public_send(k)] })
      Lutaml::Model::Lml::OrderedContent.apply(descriptor(fresh), tokens, target)
      expect(target.to_xml).to eq(para.from_xml(xml).to_xml)
    end

    it "makes a model that declares ordered_content an ordered mapping" do
      bundle = fx.bundle_for(LmlOrderFixtures::Transport)
      expect(bundle["models"].values.first["mappings"]["xml"]).not_to have_key("mixed_content")
      bundle["models"].values.first["mappings"]["xml"].delete("ordered")
      mapping = compile(bundle)["LmlOrderFixtures::Transport@default"].mappings_for(:xml)
      expect(mapping).to be_ordered
    end

    it "refuses a malformed ordered_content descriptor and the reserved member" do
      bad = Marshal.load(Marshal.dump(bundle))
      bad["models"]["LmlOrderFixtures::Para@default"]["ordered_content"] = { "member" => "x", "version" => 1 }
      expect(refusal(bad)&.reason).to eq(:invalid_ordered_content)

      reserved = Marshal.load(Marshal.dump(bundle))
      reserved["models"]["LmlOrderFixtures::Para@default"]["attributes"] <<
        { "name" => "__lml_content", "type" => { "kind" => "builtin", "name" => "string" } }
      expect(refusal(reserved, into: stub_const("LmlMapGenTwo", Module.new))&.reason).to eq(:reserved_member)
    end
  end

  describe "polymorphism" do
    let(:bundle) { fx.with_discriminator(fx.bundle_for(fx::Shape, fx::Circle)) }

    it "resolves cases to installed constants and round-trips them" do
      classes = compile(bundle)
      shape = classes["LmlMappingFixtures::Shape@default"]
      rule = shape.mappings_for(:xml).mappings.first
      expect(rule.polymorphic).to eq(attribute: :kind, class_map: { "circle" => "LmlMapGen::Circle" })
      json_rule = shape.mappings_for(:json).mappings.first
      expect(json_rule.polymorphic).to eq(attribute: :kind, class_map: { "circle" => "LmlMapGen::Circle" })
    end

    it "refuses a case target that is not in the model map" do
      error = refusal(Marshal.load(Marshal.dump(bundle)).tap do |b|
        b["models"]["LmlMappingFixtures::Shape@default"]["mappings"]["xml"]["rules"][0]["discriminator"]["cases"]["circle"] = "Nope@default"
      end)
      expect(error).to have_attributes(reason: :unknown_discriminator)
    end

    it "refuses a target with no installed constant (Ruby resolves by Object.const_get)" do
      classes = bundle["models"].keys.to_h { |id| [id, Class.new(Lutaml::Model::Serializable)] }
      bundle["models"].each { |id, doc| fx.declare_attributes(classes[id], doc, classes) }
      expect { described_class.apply(classes, bundle) }
        .to raise_error(rejected) { |e| expect(e.reason).to eq(:unsupported_mapping) }
    end
  end

  describe "refusals" do
    {
      "an unknown format" => [->(m) { m["toml"] = { "rules" => [] } }, :unsupported_format],
      "an xml sequence" => [->(m) { m["xml"]["sequence"] = ["x"] }, :unsupported_mapping],
      "a sequence rule" => [->(m) { m["xml"]["rules"][0]["kind"] = "sequence" }, :unsupported_mapping],
      "format-level root_mappings" => [->(m) { m["json"]["root_mappings"] = { "a" => "b" } }, :unsupported_mapping],
      "an executable key" => [->(m) { m["xml"]["rules"][0]["with"] = {} }, :unsupported_mapping],
      "polymorphic_map" => [->(m) { m["xml"]["rules"][0]["polymorphic_map"] = {} }, :unsupported_mapping],
      "a missing target" => [->(m) { m["xml"]["rules"][0].delete("to") }, :unsupported_mapping],
      "an unknown target" => [->(m) { m["xml"]["rules"][0]["to"] = "ghost" }, :dangling_reference],
      "an unknown render policy" => [->(m) { m["xml"]["rules"][0]["render"] = { "nil" => "shrug" } }, :unsupported_mapping],
      "an unknown render slot" => [->(m) { m["xml"]["rules"][0]["render"] = { "blank" => "omit" } }, :unsupported_mapping],
      "an alias-less name" => [->(m) { m["xml"]["rules"][0]["name"] = [] }, :invalid_document],
      "cdata on an attribute" => [->(m) { m["xml"]["rules"].find { |r| r["kind"] == "attribute" }["cdata"] = true }, :unsupported_mapping],
      "as_blank for json" => [->(m) { m["json"]["rules"][0]["render"] = { "nil" => "as_blank" } }, :unsupported_mapping],
    }.each do |label, (mutation, reason)|
      it "refuses #{label} by name (#{reason})" do
        error = refusal(edited { |m| mutation.call(m) })
        expect(error).to be_a(rejected)
        expect(error.reason).to eq(reason)
        expect(error.model_id).to eq("LmlMappingFixtures::Doc@default")
      end
    end

    it "refuses a class that already has the mapping" do
      bundle = fx.bundle_for(fx::Item)
      classes = fx.fresh_classes(bundle, holder)
      described_class.apply(classes, bundle)
      expect { described_class.apply(classes, bundle) }.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:unsupported_mapping)
      }
    end

    it "refuses a model that is missing from the model map" do
      bundle = fx.bundle_for(fx::Item)
      expect { described_class.apply({}, bundle) }.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:dangling_reference)
      }
    end

    it "declares nothing when any model is refused" do
      bundle = edited { |m| m["xml"]["rules"][0]["to"] = "ghost" }
      classes = fx.fresh_classes(bundle, holder)
      expect { described_class.apply(classes, bundle) }.to raise_error(rejected)
      expect(classes.values.map { |k| k.mappings.keys }).to all(be_empty)
    end
  end

  describe "composition with the validator" do
    it "accepts what the validator accepted for a plain model" do
      bundle = fx.bundle_for(fx::Doc, fx::Item, fx::Entry)
      validated = Lutaml::Model::Lml::DocumentValidator.validate!(bundle, kind: :bundle)
      expect(validated).to be_frozen
      classes = fx.fresh_classes(validated, holder)
      expect(described_class.apply(classes, validated)).to equal(classes)
    end
  end
end
