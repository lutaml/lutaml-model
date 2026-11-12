# frozen_string_literal: true

require "spec_helper"
require_relative "../../../scripts/lml/export_mml"
require "tmpdir"

RSpec.describe LmlMml do
  let(:directory) { described_class::PACKAGE }
  let(:manifest) { JSON.parse(File.read(File.join(directory, "manifest.json"))) }
  let(:oracles) { JSON.parse(File.read(File.join(directory, "oracle.json"))).fetch("cases") }
  let(:inventory) { JSON.parse(File.read(File.join(directory, "inventory.json"))) }
  let(:temporary) { Dir.mktmpdir("lml-mml") }

  let(:payloads) { described_class.files }

  # Regeneration needs the pinned mml 2.4.7 source (never a runtime or
  # development dependency: mml pins its own lutaml-model range). Specs that
  # read only the committed package always run.
  def require_source
    described_class.source_root
  rescue ArgumentError
    skip "pinned mml #{described_class::SOURCE_VERSION} source not installed (set LML_MML_ROOT)"
  end

  after { FileUtils.remove_entry(temporary) }

  it "pins the real source revision, version, library bytes and framework dependency" do
    expect(manifest).to include(
      "source_revision" => "d826d80f6b1477569c8320ccd945268a6ce1062f",
      "source_version" => "2.4.7", "source_digest" => described_class::SOURCE_DIGEST,
      "framework_revision" => described_class::FRAMEWORK_REVISION,
      "preservation_revision" => "9716740b6b7feb755b8557a2bfab89d066e855bd"
    )
    require_source
    expect(described_class.source_digest(described_class.source_root)).to eq(described_class::SOURCE_DIGEST)
  end

  it "refuses a changed source before loading any of its Ruby code" do
    FileUtils.mkdir_p(File.join(temporary, "lib"))
    File.write(File.join(temporary, "lib/mml.rb"), 'raise "must not execute"')
    expect { described_class.load_source(temporary) }.to raise_error(ArgumentError, /source digest differs/)
  end

  it "exports all four closed graphs, including both Math graphs with the portable float" do
    graphs = manifest.fetch("graphs")
    expect(graphs.keys).to contain_exactly("v3-mi-mixed", "v3-math-nested", "v4-mi-mixed", "v4-math-nested")
    expect(graphs.values.map { |graph| graph.key?("refusal") }).to all(be(false))
    expect(graphs.transform_values { |graph| graph.fetch("model_count") }).to eq(
      "v3-mi-mixed" => 3, "v3-math-nested" => 194, "v4-mi-mixed" => 3, "v4-math-nested" => 195,
    )
    %w[v3 v4].each do |version|
      bundle = Lutaml::Model::Lml::Importer.bundle(File.read(File.join(directory, "#{version}-math-nested.json")))
      expect(bundle.checksum).to eq(graphs.fetch("#{version}-math-nested").fetch("checksum"))
      scripts = bundle.models.fetch("Mml::V#{version.delete_prefix('v')}::Mscarries@mml_#{version}")
        .fetch("attributes").find { |attribute| attribute["name"] == "scriptsizemultiplier" }
      expect(scripts.fetch("type")).to eq("kind" => "builtin", "name" => "float")
    end
  end

  it "passes the completeness check with every closed graph exported" do
    require_source
    report = described_class.check(directory, payloads, require_complete: true)
    expect(report).to include("exported_count" => 4, "refused" => {}, "errors" => [])
  end

  it "retains all child references of the Mi graphs, including every referenced model" do
    %w[v3 v4].each do |version|
      register = "mml_#{version}"
      bundle = Lutaml::Model::Lml::Importer.bundle(File.read(File.join(directory, "#{version}-mi-mixed.json")))
      expect { Lutaml::Model::Lml::DocumentValidator.validate!(bundle.to_h, kind: :bundle) }.not_to raise_error
      graph = manifest.fetch("graphs").fetch("#{version}-mi-mixed")
      expect(bundle.checksum).to eq(graph.fetch("checksum"))
      references = graph.fetch("source_references")
      expect(bundle.models.keys).to match_array(references.keys)
      expect(references.values.flatten.uniq - bundle.models.keys).to be_empty
      expect(bundle.models.keys).to include("Mml::V#{version.delete_prefix('v')}::Mi@#{register}")
      expect(YAML.safe_load_file(File.join(directory, "#{version}-mi-mixed.yaml"), aliases: false)).to eq(bundle.to_h)
    end
  end

  it "captures real mixed text and inline element order in both source versions" do
    oracles.select { |entry| entry.fetch("id").include?("mi-mixed") }.each do |entry|
      data = entry.fetch("expected").fetch("data")
      expect(data.fetch("value")).to eq(%w[x y z])
      expect(data.fetch("__lml_content").map { |token| token.fetch("attribute") }).to eq(
        %w[value malignmark_value value mglyph_value value],
      )
      expect(data.fetch("mglyph_value").first).to include("src" => "g.png", "alt" => "g")
      expect(entry.fetch("expected").fetch("output")).to eq(entry.fetch("input"))
    end
  end

  it "captures ordinary and recursive child order instead of grouping repeated members" do
    oracles.select { |entry| entry.fetch("id").include?("math-nested") }.each do |entry|
      data = entry.fetch("expected").fetch("data")
      expect(data.fetch("__lml_content").map { |token| token.fetch("attribute") }).to eq(%w[mrow_value mi_value])
      row = data.fetch("mrow_value").first
      expect(row.fetch("__lml_content").map { |token| token.fetch("attribute") }).to eq(
        %w[mi_value mo_value mfrac_value mi_value],
      )
      fraction = row.fetch("mfrac_value").first
      expect(fraction.fetch("__lml_content").map { |token| token.fetch("attribute") }).to eq(%w[mi_value mrow_value])
      expect(fraction.fetch("mi_value").first.fetch("value")).to eq(%w[x y])
      expect(fraction.fetch("mrow_value").first.fetch("mn_value").map { |node| node.fetch("value") }).to eq([["1"], ["2"]])
      tree = entry.fetch("expected").fetch("tree")
      expect(tree.first).to eq([described_class::NAMESPACE, "math"])
    end
  end

  it "reports every source ordered model as exported, including the float-bearing Mscarries" do
    versions = inventory.fetch("versions")
    expect(versions.map { |entry| entry.values_at("register", "registered_count", "source_ordered_count", "exported_ordered_count", "float_ordered_count") }).to eq(
      [["mml_v2", 189, 62, 62, 1], ["mml_v3", 194, 64, 64, 1], ["mml_v4", 195, 65, 65, 1]],
    )
    expect(versions.sum { |entry| entry.fetch("source_ordered_count") }).to eq(191)
    versions.each do |version|
      expect(version.fetch("exported_count")).to eq(version.fetch("registered_count"))
      expect(version.fetch("declarations").select { |entry| entry.key?("reason") }).to eq([])
      mscarries = version.fetch("declarations").find { |entry| entry["model"] == "#{version.fetch('version')}::Mscarries" }
      expect(mscarries).to include("source_ordered" => true, "ordered_content" => true,
                                   "float_attributes" => ["scriptsizemultiplier"])
    end
    exclusions = inventory.fetch("existing_exclusions")
    expect(exclusions).to include("reported_historical_ordered_refusals" => 191, "historical_ordered_model_count_matched" => true)
    expect(exclusions.fetch("v3").fetch("existing_filters")).to include("share requires XInclude", "ErrorHandling")
    expect(exclusions.fetch("v3").fetch("negative_tests_pending")).to eq("Parser does not validate MathML schema compliance")
    expect(exclusions.fetch("v4").fetch("existing_filters")).to include("mtd outside table")
  end

  it "pins regenerated payload bytes and all manifest digests" do
    require_source
    payloads.each { |path, bytes| expect(File.binread(File.join(directory, path))).to eq(bytes.b) }
    manifest.fetch("files").each do |entry|
      expect(LmlPreservation.digest(File.binread(File.join(directory, entry.fetch("path"))))).to eq(entry.fetch("sha256"))
    end
  end

  it "reports changed and unknown package files without rewriting them" do
    require_source
    FileUtils.cp_r("#{directory}/.", temporary)
    File.write(File.join(temporary, "oracle.json"), "{}")
    File.write(File.join(temporary, "unknown.json"), "{}")
    expect(described_class.check(temporary, payloads).fetch("errors")).to include(
      { "id" => "oracle.json", "error" => "missing or changed file" },
      { "id" => "unknown.json", "error" => "unknown file" },
    )
    expect(File.read(File.join(temporary, "oracle.json"))).to eq("{}")
  end
end
