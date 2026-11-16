# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../lib/lutaml/model/lml/artifact_verifier"

RSpec.describe Lutaml::Model::Lml::ArtifactVerifier do
  let(:fixtures) { File.expand_path("../../fixtures/lml_artifacts", __dir__) }
  let(:manifest) { JSON.parse(File.read(File.join(fixtures, "valid.json"))) }
  let(:pin) { File.read(File.join(fixtures, "valid.sha256")).strip }
  let(:artifact_root) { Dir.mktmpdir("lml-artifact") }
  let(:verifier) { described_class.new(root: artifact_root, expected_sha256: pin) }

  before { FileUtils.cp(File.join(fixtures, "model.json"), artifact_root) }
  after { FileUtils.remove_entry(artifact_root) }

  it "verifies the caller-pinned fixture and freezes the verified manifest" do
    verified = verifier.verify(manifest)
    expect(verified).to equal(manifest)
    expect(verified.fetch("files").first).to be_frozen
    expect { verified.fetch("files") << {} }.to raise_error(FrozenError)
  end

  it "ignores object key order but preserves semantic array order in checksums" do
    expect(described_class.checksum(manifest.to_a.reverse.to_h)).to eq(pin)
    expect(described_class.checksum(["xml", "json"])).not_to eq(described_class.checksum(["json", "xml"]))
  end

  it "rejects a wrong expected manifest digest before using files" do
    verifier = described_class.new(root: artifact_root, expected_sha256: "sha256:#{'0' * 64}")
    expect { verifier.verify(manifest) }.to raise_error(described_class::Error, %r{checksum_mismatch: /manifest})
  end

  %w[lml_checksum generator_version target corpora dependencies].each do |field|
    it "rejects an altered #{field} pin" do
      changed = manifest.merge(field => case field
                                        when "corpora", "dependencies" then []
                                        when "lml_checksum" then "sha256:#{'1' * 64}"
                                        when "target" then "wasm"
                                        else "changed"
                                        end)
      expect { verifier.verify(changed) }.to raise_error(described_class::Error, /checksum_mismatch/)
    end
  end

  it "rejects an unsupported schema version with a named error" do
    expect { verifier.verify(manifest.merge("schema_version" => 999)) }
      .to raise_error(described_class::Error, %r{unsupported_version: /schema_version})
  end

  it "rejects corrupt artifact bytes" do
    File.write(File.join(artifact_root, "model.json"), "changed")
    expect { verifier.verify(manifest) }.to raise_error(described_class::Error, %r{checksum_mismatch: /files/0})
  end

  it "rejects absent artifact files" do
    FileUtils.rm(File.join(artifact_root, "model.json"))
    expect { verifier.verify(manifest) }.to raise_error(described_class::Error, /invalid_document/)
  end

  ["../outside", "/absolute", "nested/../outside", "a//b", "C:/outside", "a\\b"].each do |path|
    it "rejects non-relative artifact path #{path.inspect}" do
      changed = manifest.merge("files" => [{ "path" => path, "sha256" => manifest["files"][0]["sha256"] }])
      pinned = described_class.new(root: artifact_root, expected_sha256: described_class.checksum(changed))
      expect { pinned.verify(changed) }.to raise_error(described_class::Error, /invalid_document/)
    end
  end

  it "rejects a symlink that escapes the artifact root" do
    outside = File.join(fixtures, "model.json")
    FileUtils.rm(File.join(artifact_root, "model.json"))
    File.symlink(outside, File.join(artifact_root, "model.json"))
    expect { verifier.verify(manifest) }.to raise_error(described_class::Error, /invalid_document/)
  end

  it "compares supplied consumer pins even when a different manifest is validly checksummed" do
    strict = described_class.new(root: artifact_root, expected_sha256: pin,
                                 target: "rust", lml_checksum: manifest["lml_checksum"])
    expect { strict.verify(manifest) }.to raise_error(described_class::Error, %r{checksum_mismatch: /target})
  end

  it "refuses non-neutral values and ambiguous object keys" do
    expect { described_class.checksum("value" => 0.1) }.to raise_error(described_class::Error, /non-neutral/)
    expect { described_class.checksum(value: "x") }.to raise_error(described_class::Error, /keys must be strings/)
  end
end
