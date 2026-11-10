# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/lml"
require "tmpdir"
require "digest"

RSpec.describe "LML input hardening (RB-INPUT)" do
  let(:lml) { Lutaml::Model::Lml }
  let(:validator) { lml::DocumentValidator }
  let(:verifier) { lml::ArtifactVerifier }

  def bundle_hash(attributes: nil)
    attributes ||= [{ "name" => "label", "type" => { "kind" => "builtin", "name" => "string" } }]
    { "lml_bundle" => 1, "roots" => ["Hard::Node@default"],
      "models" => { "Hard::Node@default" => { "lml" => 2, "model" => "Hard::Node", "register" => "default",
                                              "attributes" => attributes } },
      "value_types" => {}, "capabilities" => ["json"] }
  end

  def refusal
    yield
    nil
  rescue lml::RejectedError => e
    e
  end

  describe "M1: JSON comments" do
    it "refuses a // comment" do
      text = "{ // note\n#{JSON.generate(bundle_hash).delete_prefix('{')}"
      error = refusal { lml::Importer.bundle(text) }
      expect([error&.reason]).to eq([:invalid_document])
    end

    it "refuses a /* */ comment hiding a duplicate key" do
      text = %({"lml_bundle":1,"roots":[]/*"*/,"roots":[]/*"*/,"models":{},"value_types":{},"capabilities":[]})
      error = refusal { lml::Importer.bundle(text) }
      expect([error&.reason, error&.detail]).to eq([:invalid_document, "not valid JSON: comments are not allowed"])
    end

    it "still accepts a slash inside a string" do
      text = JSON.generate(bundle_hash(attributes: [{ "name" => "a", "type" => { "kind" => "builtin", "name" => "string" },
                                                      "default" => { "present" => true, "value" => "a//b/*c*/" } }]))
      expect(lml::Importer.bundle(text).roots).to eq(["Hard::Node@default"])
    end
  end

  describe "M7: default of the wrong type" do
    [7, -0, true, { "a" => 1 }].each do |value|
      it "refuses #{value.inspect} on a string attribute" do
        attrs = [{ "name" => "label", "type" => { "kind" => "builtin", "name" => "string" },
                   "default" => { "present" => true, "value" => value } }]
        error = refusal { validator.validate!(bundle_hash(attributes: attrs), kind: :bundle) }
        expect(error&.reason).to eq(:non_serializable_default)
      end
    end

    it "refuses a string on an integer attribute and accepts a matching one" do
      mk = lambda { |v|
        [{ "name" => "n", "type" => { "kind" => "builtin", "name" => "integer" },
           "default" => { "present" => true, "value" => v } }]
      }
      expect(refusal { validator.validate!(bundle_hash(attributes: mk.call("7")), kind: :bundle) }&.reason)
        .to eq(:non_serializable_default)
      expect(refusal { validator.validate!(bundle_hash(attributes: mk.call(7)), kind: :bundle) }).to be_nil
    end
  end

  describe "R1: invalid UTF-8 text" do
    it "raises a named error, not ArgumentError" do
      text = %({"lml_bundle":1,"x":"\xFF"}).b
      error = refusal { lml::Importer.bundle(text) }
      expect(error&.reason).to eq(:invalid_document)
    end

    it "does the same for a UTF-8 tagged string" do
      text = (+%({"lml_bundle":1,"x":"\xFF"})).force_encoding("UTF-8")
      expect(refusal { lml::Importer.bundle(text) }&.reason).to eq(:invalid_document)
    end
  end

  describe "R2: v1 non-finite defaults" do
    [Float::NAN, Float::INFINITY].each do |value|
      it "refuses #{value} at validation" do
        doc = { "lml" => 1, "model" => "A",
                "attributes" => [{ "name" => "f", "type" => "float", "default" => value }], "mappings" => {} }
        error = refusal { lml::Document.from_hash(doc) }
        expect(error&.reason).to eq(:invalid_document)
      end
    end

    it "still accepts a finite v1 float" do
      doc = { "lml" => 1, "model" => "A", "attributes" => [{ "name" => "f", "default" => 1.5 }], "mappings" => {} }
      expect { lml::Document.from_hash(doc).checksum }.not_to raise_error
    end
  end

  describe "R4: ArtifactVerifier depth" do
    it "refuses deep nesting with a named error" do
      deep = 1
      100_000.times { deep = [deep] }
      expect { verifier.checksum("a" => deep) }.to raise_error(verifier::Error) { |e| expect(e.reason).to eq(:invalid_document) }
    end

    it "accepts nesting within the limit" do
      deep = 1
      50.times { deep = [deep] }
      expect(verifier.checksum("a" => deep)).to match(/\Asha256:/)
    end
  end

  describe "R5: case-exact artifact paths" do
    it "refuses A.TXT when the file is a.txt" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "a.txt"), "hi")
        sha = "sha256:#{Digest::SHA256.hexdigest('hi')}"
        manifest = lambda { |path|
          { "manifest" => 1, "schema_version" => 2, "target" => "ruby", "lml_checksum" => "sha256:#{'0' * 64}",
            "generator_version" => "1", "capabilities" => [], "corpora" => [], "dependencies" => [],
            "files" => [{ "path" => path, "sha256" => sha }] }
        }
        ok = manifest.call("a.txt")
        expect { verifier.new(root: root, expected_sha256: verifier.checksum(ok)).verify(ok) }.not_to raise_error
        bad = manifest.call("A.TXT")
        expect { verifier.new(root: root, expected_sha256: verifier.checksum(bad)).verify(bad) }
          .to raise_error(verifier::Error) { |e| expect(e.reason).to eq(:invalid_document) }
      end
    end
  end

  describe "R6: import wording" do
    it "does not say export" do
      error = refusal { lml::Importer.bundle("{not json") }
      expect(error.message).to include("cannot import")
      expect(error.message).not_to include("export")
    end

    it "keeps export wording for export errors" do
      expect(lml::RejectedError.new(:custom_initialize, "Foo", "x").message).to start_with("cannot export")
    end
  end

  describe "R7: v1 model names" do
    ["x; 1", "lower", "A::", "A B", ""].each do |name|
      it "refuses #{name.inspect}" do
        error = refusal { lml::Document.from_hash("lml" => 1, "model" => name, "attributes" => [], "mappings" => {}) }
        expect([error&.reason, error&.location]).to eq([:invalid_document, "/model"])
      end
    end

    it "accepts a constant path" do
      expect(lml::Document.from_hash("lml" => 1, "model" => "A::B", "attributes" => [], "mappings" => {}).model_name)
        .to eq("A::B")
    end
  end
end
