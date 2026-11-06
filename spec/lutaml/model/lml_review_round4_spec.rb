# frozen_string_literal: true

require "json"
require "benchmark"
require "open3"
require "tmpdir"
require "digest"
require "lutaml/model/lml"

RSpec.describe "LML review round-3 probe fixes (importer, bundle, verifier)" do
  let(:lml) { Lutaml::Model::Lml }
  let(:root_dir) { File.expand_path("../../..", __dir__) }
  let(:klass) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :a, :string
      json { map "a", to: :a }
    end
  end

  before { stub_const("R4Leaf", klass) }

  def bundle_hash
    lml.export_bundle([R4Leaf]).to_h
  end

  def rejection
    yield
    nil
  rescue lml::RejectedError => e
    e
  end

  describe "importer text scanning" do
    it "refuses an unterminated string in linear time" do
      text = "{\"lml_bundle\":1,\"x\":\"#{'\\"' * 100_000}"
      error = nil
      seconds = Benchmark.realtime { error = rejection { lml::Importer.import(text) } }

      expect(error.reason).to eq(:invalid_document)
      expect(seconds).to be < 1
    end

    it "refuses runaway nesting before parsing it all" do
      text = '{"a":' * 200_000
      error = nil
      seconds = Benchmark.realtime { error = rejection { lml::Importer.import(text) } }

      expect(error.reason).to eq(:invalid_document)
      expect(seconds).to be < 1
    end

    it "still rejects duplicate keys and comments" do
      expect(rejection { lml::Importer.import('{"a":1,"a":2}') }.detail).to include("duplicate key")
      expect(rejection { lml::Importer.import('{"a":1 /* c */}') }.detail).to include("comments")
    end

    %w[UTF-16LE UTF-16BE UTF-32LE].each do |encoding|
      it "refuses #{encoding} text with a RejectedError" do
        text = JSON.generate(bundle_hash).encode(encoding)

        expect(rejection { lml::Importer.import(text) }.reason).to eq(:invalid_document)
      end
    end
  end

  describe "importer namespace" do
    it "refuses a non-module namespace" do
      expect(rejection { lml::Importer.import(bundle_hash, namespace: "String") }.reason)
        .to eq(:invalid_document)
    end

    it "refuses a frozen module namespace" do
      expect(rejection { lml::Importer.import(bundle_hash, namespace: Module.new.freeze) }.reason)
        .to eq(:invalid_document)
    end

    it "refuses symbol-keyed hashes, as documented" do
      expect(rejection { lml::Importer.import({ lml_bundle: 1 }) }.detail).to include("non-string key")
    end
  end

  describe "RoundTrip.verify_materialization" do
    it "refuses a bundle in an unregistered register" do
      json = JSON.generate(bundle_hash).gsub("@default", "@zz").gsub('"register":"default"', '"register":"zz"')
      error = rejection { lml::RoundTrip.verify_materialization(JSON.parse(json)) }

      expect(error).to be_a(lml::RejectedError)
      expect(error.detail).to include("not registered")
    end

    it "verifies a bundle in the default register" do
      expect(lml::RoundTrip.verify_materialization(bundle_hash)).to eq(lml::Importer.bundle(bundle_hash))
    end
  end

  describe "Bundle" do
    it "serialises with to_json like a Document" do
      bundle = lml.export_bundle([R4Leaf])

      expect(JSON.parse(bundle.to_json)).to eq(bundle.to_h)
      expect(lml::Importer.import(bundle.to_json).keys).to eq(["R4Leaf@default"])
    end

    it "refuses the same model under two registers at export" do
      Lutaml::Model::GlobalRegister.register(Lutaml::Model::Register.new(:r4alt))
      error = rejection { lml.export_bundle([[R4Leaf, "default"], [R4Leaf, "r4alt"]]) }

      expect(error.reason).to eq(:duplicate_id)
    ensure
      Lutaml::Model::GlobalRegister.remove(:r4alt) if Lutaml::Model::GlobalRegister.respond_to?(:remove)
    end

    it "refuses cyclic provenance with a RejectedError" do
      cycle = {}
      cycle["a"] = cycle

      expect(rejection { lml.export_bundle([R4Leaf], provenance: cycle) }.reason).to eq(:invalid_document)
    end

    it "refuses provenance the importer would refuse" do
      expect(rejection { lml.export_bundle([R4Leaf], provenance: { "t" => Time.now }) }.reason)
        .to eq(:invalid_document)
      expect(rejection { lml.export_bundle([R4Leaf], provenance: { "x" => Float::NAN }) }.reason)
        .to eq(:invalid_document)
    end

    it "keeps symbol-keyed provenance, stringified, and importable" do
      bundle = lml.export_bundle([R4Leaf], provenance: { tool: "t" })

      expect(bundle.provenance).to eq("tool" => "t")
      expect(lml::Importer.import(bundle.to_json).keys).to eq(["R4Leaf@default"])
    end
  end

  describe "ArtifactVerifier non-Error leaks" do
    let(:dir) { Dir.mktmpdir }
    let(:sha) { ->(content) { "sha256:#{Digest::SHA256.hexdigest(content)}" } }

    after do
      FileUtils.chmod(0o644, Dir.glob("#{dir}/*"))
      FileUtils.remove_entry(dir)
    end

    def manifest(files, extra = {})
      { "manifest" => 1, "schema_version" => 2, "target" => "ruby", "lml_checksum" => sha.call("x"),
        "generator_version" => "1", "capabilities" => [], "corpora" => [], "dependencies" => [],
        "files" => files }.merge(extra)
    end

    def verify(root, manifest, expected: manifest)
      verifier = lml::ArtifactVerifier.new(root: root, expected_sha256: lml::ArtifactVerifier.checksum(expected))
      verifier.verify(manifest)
    rescue lml::ArtifactVerifier::Error => e
      e
    end

    it "reports a UTF-16 checksum as invalid_document" do
      File.write("#{dir}/a.txt", "A")
      files = [{ "path" => "a.txt", "sha256" => sha.call("A") }]
      result = verify(dir, manifest(files, "lml_checksum" => "x".encode("UTF-16LE")),
                      expected: manifest(files))

      expect(result.reason).to eq(:invalid_document)
    end

    it "reports an unreadable file as invalid_document" do
      File.write("#{dir}/u.txt", "U")
      File.chmod(0, "#{dir}/u.txt")
      skip "root can read mode-000 files" if File.readable?("#{dir}/u.txt")
      result = verify(dir, manifest([{ "path" => "u.txt", "sha256" => sha.call("U") }]))

      expect([result.reason, result.location]).to eq([:invalid_document, "/files/0/path"])
    end

    it "reports an empty root as invalid_document" do
      error = begin
        lml::ArtifactVerifier.new(root: "", expected_sha256: sha.call("x"))
      rescue lml::ArtifactVerifier::Error => e
        e
      end

      expect([error.reason, error.location]).to eq([:invalid_document, "/root"])
    end

    it "prints a verdict line for a non-UTF-8 manifest" do
      File.binwrite("#{dir}/m.json", "\xff\xfe")
      out, err, status = Open3.capture3(RbConfig.ruby, "scripts/lml/verify_artifacts.rb",
                                        "--manifest", "#{dir}/m.json",
                                        "--expected-sha256", sha.call("x"), chdir: root_dir)

      expect([status.exitstatus, out]).to eq([1, ""])
      expect(JSON.parse(err)).to include("verified" => false)
    end
  end
end
