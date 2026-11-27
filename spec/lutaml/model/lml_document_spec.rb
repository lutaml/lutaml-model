# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/lml/document_validator"
require "json"
require "yaml"

# lutaml-model#1033 card 01: the agreed document contract. The validator
# accepts v1 unchanged and strict v2 documents/bundles/manifests, and
# refuses everything else with a named code and a JSON-pointer location.
RSpec.describe Lutaml::Model::Lml::DocumentValidator do
  let(:fixtures) { File.expand_path("../../fixtures/lml_contract", __dir__) }
  let(:rejected) { Lutaml::Model::Lml::RejectedError }
  let(:legacy_doc) { fixture("v1_unit.json") }
  let(:v2) { fixture("v2_node.json") }
  let(:bundle) { fixture("bundle.json") }
  let(:manifest) { fixture("manifest.json") }
  let(:model_scoped_codes) { %i[lambda_default reserved_member duplicate_id] }

  def fixture(name)
    JSON.parse(File.read(File.join(fixtures, name)))
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end

  def validate(hash, kind: :document)
    described_class.validate!(hash, kind: kind)
  end

  def refusal(hash, kind: :document)
    validate(hash, kind: kind)
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  describe "valid input" do
    it "accepts a v1 document, a v2 document, a bundle and a manifest" do
      expect(validate(legacy_doc)["lml"]).to eq(1)
      expect(validate(v2)["lml"]).to eq(2)
      expect(validate(bundle, kind: :bundle)["lml_bundle"]).to eq(1)
      expect(validate(manifest, kind: :manifest)["manifest"]).to eq(1)
    end

    it "returns a deeply immutable tree and leaves the input untouched" do
      tree = validate(v2)
      expect(tree).to be_frozen
      expect(tree["attributes"].first["type"]).to be_frozen
      expect(tree["attributes"].first["name"]).to be_frozen
      expect(v2).not_to be_frozen
    end

    it "ignores unknown v1 keys (legacy tolerance) but never in v2" do
      expect(refusal(legacy_doc.merge("extra" => 1))).to be_nil
      expect(refusal(v2.merge("extra" => 1)).reason).to eq(:invalid_document)
    end
  end

  describe "version handling" do
    it "refuses an unknown document version instead of rewriting it" do
      error = refusal(v2.merge("lml" => 999))
      expect(error.reason).to eq(:unsupported_version)
      expect(error.location).to eq("/lml")
    end

    it "refuses unknown bundle and manifest versions" do
      expect(refusal(bundle.merge("lml_bundle" => 2), kind: :bundle).reason).to eq(:unsupported_version)
      expect(refusal(manifest.merge("manifest" => 2), kind: :manifest).reason).to eq(:unsupported_version)
      expect(refusal(manifest.merge("schema_version" => 3), kind: :manifest).reason).to eq(:unsupported_version)
    end

    it "refuses a v1 document inside a v2 bundle" do
      b = deep_copy(bundle)
      b["models"]["Example::Node@default"]["lml"] = 1
      expect(refusal(b, kind: :bundle).reason).to eq(:unsupported_version)
    end
  end

  describe "Document.from_hash" do
    # old-red: before this card from_hash rewrote any supplied version to 1,
    # so an unsupported `lml` was silently dropped and a v1 document came back.
    it "does not silently rewrite an unsupported lml version" do
      expect { Lutaml::Model::Lml::Document.from_hash(legacy_doc.merge("lml" => 999)) }
        .to raise_error(rejected, /unsupported_version/)
    end

    it "keeps v1 identity: same canonical form and checksum" do
      doc = Lutaml::Model::Lml::Document.from_hash(legacy_doc)
      expect(doc.to_h["lml"]).to eq(1)
      expect(doc.canonical_json).to eq(File.read(File.join(fixtures, "v1_unit.canonical.json")))
      expect(doc.checksum).to eq("sha256:04b66d5ff963c422758bce40377498c7f466645c215f19bccc5936d78468911b")
    end

    it "keeps the v2 version and pins canonical JSON and checksum" do
      doc = Lutaml::Model::Lml::Document.from_hash(v2)
      canonical = File.binread(File.join(fixtures, "v2_node.canonical.json"))
      expect(doc.to_h["lml"]).to eq(2)
      expect(doc.canonical_json.b).to eq(canonical)
      expect(canonical.dup.force_encoding("UTF-8")).to include("café/x")
      expect(doc.checksum).to eq("sha256:b4b3f994b6069fe2982f8de18a40df0f044d85d000912dc97044201c7785bf43")
      expect(doc.checksum).to eq("sha256:#{Digest::SHA256.file(File.join(fixtures, 'v2_node.canonical.json')).hexdigest}")
    end

    it "gives v2 a key-order independent canonical form" do
      shuffled = v2.to_a.reverse.to_h
      shuffled["attributes"] = shuffled["attributes"].map { |a| a.to_a.reverse.to_h }
      expect(Lutaml::Model::Lml::Document.from_hash(shuffled).checksum)
        .to eq(Lutaml::Model::Lml::Document.from_hash(v2).checksum)
    end

    it "round-trips v2 through YAML to the same tree" do
      doc = Lutaml::Model::Lml::Document.from_hash(v2)
      reloaded = YAML.safe_load(doc.to_yaml, permitted_classes: [], aliases: false)
      expect(Lutaml::Model::Lml::Document.from_hash(reloaded).checksum).to eq(doc.checksum)
    end

    it "reports a missing model as invalid_document" do
      expect { Lutaml::Model::Lml::Document.from_hash("lml" => 1) }
        .to raise_error(rejected, /invalid_document/)
    end
  end

  describe "portable float" do
    it "pins the canonical wire spelling" do
      expect([0.71, 1.0e-05, 1e20, 3.0, -0.0, 1e16, 123456789.125, 5e-324, 1.7976931348623157e308]
        .map { |value| described_class.float_wire(value) })
        .to eq(%w[0.71 1.0e-5 1.0e20 3.0 -0.0 1.0e16 123456789.125 5.0e-324 1.7976931348623157e308])
      expect { described_class.float_wire(Float::NAN) }.to raise_error(ArgumentError)
      expect { described_class.float_wire(-Float::INFINITY) }.to raise_error(ArgumentError)
    end

    it "round-trips every canonical string to the identical binary64 value" do
      [0.1, 0.71, 1.0e-05, 2.2250738585072014e-308, 9007199254740993.0, -1.5e-7, 1e22].each do |value|
        wire = described_class.float_wire(value)
        expect(described_class.canonical_float?(wire)).to be(true)
        expect(Float(wire)).to eq(value)
      end
    end

    it "accepts a canonical float default and refuses spellings that are not canonical" do
      doc = deep_copy(v2)
      doc["attributes"][1].merge!("type" => { "kind" => "builtin", "name" => "float" },
                                  "default" => { "present" => true, "value" => "0.71" })
      expect(refusal(doc)).to be_nil
      %w[0.710 +0.71 .71 1e-5 1.0E-5 1.0e+20 1.0e-05 0x1p3 NaN Infinity -Infinity].each do |spelling|
        doc["attributes"][1]["default"]["value"] = spelling
        expect(refusal(doc)&.reason).to eq(:invalid_document), spelling
      end
    end
  end

  describe "model errors" do
    def with_attribute(extra)
      doc = deep_copy(v2)
      doc["attributes"] << { "name" => "extra", "type" => { "kind" => "builtin", "name" => "string" } }.merge(extra)
      doc
    end

    {
      "lambda default" => [->(d) { d["attributes"][1]["default"] = { "lambda" => "-> { 1 }" } }, :lambda_default, "/attributes/1/default"],
      "present default without value" => [->(d) { d["attributes"][1]["default"] = { "present" => true } }, :invalid_document, "/attributes/1/default/value"],
      "custom initialize" => [->(d) { d["custom_initialize"] = true }, :custom_initialize, "/custom_initialize"],
      "imperative order" => [->(d) { d["imperative_element_order"] = true }, :imperative_element_order, "/imperative_element_order"],
      "unknown builtin type" => [->(d) { d["attributes"][1]["type"] = { "kind" => "builtin", "name" => "nope" } }, :unknown_type, "/attributes/1/type/name"],
      "unknown type kind" => [->(d) { d["attributes"][1]["type"] = { "kind" => "weird" } }, :unknown_type, "/attributes/1/type/kind"],
      "double alias" => [->(d) { d["attributes"][1]["type"] = { "kind" => "builtin", "name" => "double" } }, :unsupported_type, "/attributes/1/type/name"],
      "float default as a JSON number" => [->(d) { d["attributes"][1].merge!("type" => { "kind" => "builtin", "name" => "float" }, "default" => { "present" => true, "value" => 1.5 }) }, :invalid_document, "/attributes/1/default/value"],
      "float default non-canonical" => [->(d) { d["attributes"][1].merge!("type" => { "kind" => "builtin", "name" => "float" }, "default" => { "present" => true, "value" => "1.0e-05" }) }, :invalid_document, "/attributes/1/default/value"],
      "float default NaN" => [->(d) { d["attributes"][1].merge!("type" => { "kind" => "builtin", "name" => "float" }, "default" => { "present" => true, "value" => "NaN" }) }, :invalid_document, "/attributes/1/default/value"],
      "float default Infinity" => [->(d) { d["attributes"][1].merge!("type" => { "kind" => "builtin", "name" => "float" }, "default" => { "present" => true, "value" => "Infinity" }) }, :invalid_document, "/attributes/1/default/value"],
      "duplicate attribute" => [->(d) { d["attributes"][1]["name"] = "children" }, :duplicate_id, "/attributes/1/name"],
      "reserved member" => [->(d) { d["attributes"][1]["name"] = "__lml_content" }, :reserved_member, "/attributes/1/name"],
      "unknown format" => [->(d) { d["mappings"]["csv"] = {} }, :unsupported_format, "/mappings/csv"],
      "executable rule" => [->(d) { d["mappings"]["xml"]["rules"][0]["with"] = { "to" => "x" } }, :unsupported_mapping, "/mappings/xml/rules/0/with"],
      "unknown rule key" => [->(d) { d["mappings"]["xml"]["rules"][0]["mystery"] = 1 }, :unsupported_mapping, "/mappings/xml/rules/0/mystery"],
      "unknown namespace mode" => [->(d) { d["mappings"]["xml"]["namespace"] = { "mode" => "guess" } }, :unsupported_mapping, "/mappings/xml/namespace/mode"],
      "bad ordered content" => [->(d) { d["ordered_content"] = { "member" => "other", "version" => 1 } }, :invalid_ordered_content, "/ordered_content"],
      "float in a value" => [->(d) { d["attributes"][1]["default"] = { "present" => true, "value" => 1.5 } }, :invalid_document, "/attributes/1/default/value"],
      "oversized integer" => [->(d) { d["attributes"][1]["default"] = { "present" => true, "value" => 2**60 } }, :invalid_document, "/attributes/1/default/value"],
      "invalid register" => [->(d) { d["register"] = "has space" }, :invalid_document, "/register"],
    }.each do |name, (mutate, code, location)|
      it "refuses #{name} with #{code} at #{location}" do
        doc = with_attribute({})
        mutate.call(doc)
        error = refusal(doc)
        expect([error&.reason, error&.location]).to eq([code, location])
        expect(error.model_id).to eq("Example::Node@default") if model_scoped_codes.include?(code)
      end
    end

    it "keeps legacy reason/klass/detail on exporter errors" do
      error = rejected.new(:custom_initialize, "Foo", "has initialize")
      expect([error.reason, error.klass, error.detail, error.location]).to eq([:custom_initialize, "Foo", "has initialize", nil])
      expect(error.message).to eq("cannot export Foo to LML: custom_initialize (has initialize)")
    end
  end

  describe "bundle graph" do
    it "refuses a dangling type reference" do
      b = deep_copy(bundle)
      b["models"]["Example::Node@default"]["attributes"][0]["type"]["id"] = "Missing@default"
      error = refusal(b, kind: :bundle)
      expect([error.reason, error.location]).to eq([:dangling_reference, "/models/Example::Node@default/attributes/0/type/id"])
    end

    it "refuses a dangling root and duplicate roots" do
      b = deep_copy(bundle)
      b["roots"] = ["A@default"]
      expect(refusal(b, kind: :bundle).reason).to eq(:dangling_reference)
      b["roots"] = ["Example::Node@default", "Example::Node@default"]
      expect(refusal(b, kind: :bundle).reason).to eq(:duplicate_id)
    end

    it "refuses a model key that disagrees with its ID" do
      b = deep_copy(bundle)
      b["models"]["Example::Other@default"] = b["models"].delete("Example::Node@default")
      b["roots"] = []
      expect(refusal(b, kind: :bundle).reason).to eq(:invalid_document)
    end

    it "refuses a format missing from capabilities" do
      b = deep_copy(bundle)
      b["capabilities"] = ["json"]
      expect(refusal(b, kind: :bundle).reason).to eq(:capability_missing)
    end

    it "checks discriminator targets and their attribute" do
      b = deep_copy(bundle)
      node = b["models"]["Example::Node@default"]
      node["attributes"][1]["discriminator"] = { "attribute" => "label", "cases" => { "a" => "Example::Node@default" } }
      expect(refusal(b, kind: :bundle)).to be_nil
      node["attributes"][1]["discriminator"] = { "attribute" => "nope", "cases" => { "a" => "Example::Node@default" } }
      expect(refusal(b, kind: :bundle).reason).to eq(:unknown_discriminator)
      node["attributes"][1]["discriminator"] = { "attribute" => "label", "cases" => { "a" => "Gone@default" } }
      expect(refusal(b, kind: :bundle).reason).to eq(:dangling_reference)
    end

    it "refuses an unknown value type base" do
      b = deep_copy(bundle)
      b["value_types"]["V@default"] = { "base" => "double", "facets" => {} }
      expect(refusal(b, kind: :bundle).reason).to eq(:unsupported_type)
    end
  end

  describe "manifest" do
    it "refuses path traversal, absolute paths and unsorted files" do
      %w[../x /abs a/../b].each do |path|
        m = deep_copy(manifest)
        m["files"][0]["path"] = path
        expect(refusal(m, kind: :manifest).reason).to eq(:invalid_document)
      end
      m = deep_copy(manifest)
      m["files"] = [{ "path" => "b", "sha256" => "sha256:#{'a' * 64}" }, { "path" => "a", "sha256" => "sha256:#{'a' * 64}" }]
      expect(refusal(m, kind: :manifest).location).to eq("/files")
    end

    it "refuses a malformed digest and an unknown target" do
      m = deep_copy(manifest)
      m["lml_checksum"] = "sha256:ABC"
      expect(refusal(m, kind: :manifest).location).to eq("/lml_checksum")
      m = deep_copy(manifest)
      m["target"] = "go"
      expect(refusal(m, kind: :manifest).location).to eq("/target")
    end
  end

  describe "schema file" do
    let(:schema) { JSON.parse(File.read(File.expand_path("../../../schema/lml/document.schema.json", __dir__))) }

    it "lists the same codes, builtin types and formats as the validator" do
      defs = schema["$defs"]
      expect(defs["errorCodes"]["enum"]).to eq(rejected::CODES.map(&:to_s))
      expect(defs["builtinType"]["enum"]).to eq(described_class::BUILTIN_TYPES)
      expect(defs["formats"]["enum"]).to eq(described_class::FORMATS)
    end
  end
end
