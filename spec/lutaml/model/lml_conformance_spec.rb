# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/lml_conformance"
require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe LmlConformance do
  let(:directory) { File.expand_path("../../fixtures/lml_conformance/core", __dir__) }
  let(:index) { JSON.parse(File.read(File.join(directory, "index.json"))) }
  let(:temporary) { Dir.mktmpdir("lml-conformance") }

  after { FileUtils.remove_entry(temporary) }

  it "replays all five pinned Ruby cases and reports their identities" do
    report = described_class.check(directory)
    expect(report).to include("expected_count" => 5, "executed_count" => 5, "errors" => [])
    expect(report.fetch("executed_ids")).to eq(%w[core-json core-xml-tree core-xml-bytes core-json-invalid core-json-portable-exact])
  end

  it "pins normalized exact integer strings and false without stringifying booleans" do
    entry = index.fetch("cases").first
    expect(entry.fetch("expected_data")).to eq("label" => "café & tea", "count" => "42", "enabled" => false)
    expect(described_class.execute(entry).fetch("data")).to eq(entry.fetch("expected_data"))
  end

  it "pins named negative results without exception messages" do
    entry = index.fetch("cases").find { |item| item.fetch("id") == "core-json-invalid" }
    expect(entry.fetch("expected_error")).to eq(
      "reason" => "invalid_document", "model_id" => "LmlConformance::Record@default",
      "format" => "json", "location" => "/input"
    )
    expect(described_class.execute(entry).fetch("error")).to eq(entry.fetch("expected_error"))
  end

  it "labels native wire truth without changing the numeric Ruby serializer" do
    entry = index.fetch("cases").first
    expect(entry.fetch("wire_profile")).to eq("ruby-native-v1")
    expect(entry.fetch("input")).to eq('{"label":"café & tea","count":42,"enabled":false}')
    expect(entry.fetch("expected_output")).to eq('{"label":"café & tea","count":42,"enabled":false}')
    expect(entry.fetch("data_profile")).to eq("exact-values-decimal-v1")
  end

  it "executes the portable exact-string boundary without a floating-point intermediate" do
    entry = index.fetch("cases").last
    expect(entry.fetch("id")).to eq("core-json-portable-exact")
    expect(entry.fetch("wire_profile")).to eq("portable-exact-json-v1")
    expect(JSON.parse(entry.fetch("input"))).to include("count" => "9007199254740993")
    result = described_class.execute(entry)
    expect(result.fetch("data")).to eq("label" => "beyond binary64", "count" => "9007199254740993", "enabled" => false)
    expect(JSON.parse(result.fetch("output"))).to eq(result.fetch("data"))
    expect(result.fetch("output")).to eq(entry.fetch("expected_output"))
    expect(described_class.compare(entry, result)).to be_nil
  end

  it "refuses numeric input to the portable exact-string profile" do
    entry = index.fetch("cases").last.merge("input" => '{"label":"number","count":9007199254740993,"enabled":false}')
    expect { described_class.execute(entry) }.to raise_error(ArgumentError, "portable integer requires decimal string")
  end

  it "requires explicit portable case coverage for generated Rust and TS codecs" do
    %w[rust ts].each do |target|
      missing = described_class.coverage(index, target: target, executed_ids: ["core-json"])
      expect(missing.fetch("required_profiles")).to eq(["portable-exact-json-v1"])
      expect(missing.fetch("errors")).to eq([{ "id" => "core-json-portable-exact", "error" => "required case not executed" }])
      complete = described_class.coverage(index, target: target, executed_ids: ["core-json-portable-exact"])
      expect(complete.fetch("errors")).to be_empty
    end
    expect(described_class.coverage(index, target: "ruby", executed_ids: ["core-json-portable-exact"]).fetch("errors").size).to eq(4)
  end

  it "fails an omitted portable case even when every native case executed" do
    index.fetch("cases").pop
    report = described_class.replay(index)
    expect(report.fetch("errors")).to include(
      { "id" => "core-json-portable-exact", "error" => "missing case" },
      { "id" => "core-json-portable-exact", "error" => "required case not executed" },
    )
  end

  it "regenerates exactly the checked-in bytes and manifest digests" do
    described_class.files.each do |path, bytes|
      expect(File.binread(File.join(directory, path))).to eq(bytes.b)
    end
    manifest = JSON.parse(File.read(File.join(directory, "manifest.json")))
    manifest.fetch("files").each do |entry|
      expect(described_class.digest(File.binread(File.join(directory, entry.fetch("path"))))).to eq(entry.fetch("sha256"))
    end
  end

  it "loads JSON and safe YAML schemas as identical neutral trees" do
    expect(YAML.safe_load_file(File.join(directory, "schema.yaml"), aliases: false)).to eq(
      JSON.parse(File.read(File.join(directory, "schema.json"))),
    )
  end

  it "fails missing cases by ID" do
    index.fetch("cases").shift
    expect(described_class.replay(index).fetch("errors")).to include("id" => "core-json", "error" => "missing case")
  end

  it "fails unknown cases by ID" do
    index.fetch("cases") << index.fetch("cases").first.merge("id" => "future-case")
    expect(described_class.replay(index).fetch("errors")).to include("id" => "future-case", "error" => "unknown case")
  end

  it "fails changed and duplicate cases by ID" do
    index.fetch("cases").first["input"] = "{}"
    index.fetch("cases") << index.fetch("cases").find { |item| item.fetch("id") == "core-json-invalid" }.dup
    expect(described_class.replay(index).fetch("errors")).to include(
      { "id" => "core-json", "error" => "changed case" },
      { "id" => "core-json-invalid", "error" => "duplicate case" },
    )
  end

  it "detects actual execution drift against unchanged pinned expectations" do
    allow(described_class).to receive(:execute).and_call_original
    entry = index.fetch("cases").first
    allow(described_class).to receive(:execute).with(entry).and_return("data" => {}, "output" => "{}")
    # Freeze the authored reference independently of the simulated runtime drift.
    allow(described_class).to receive(:oracle_cases).and_return(index.fetch("cases"))
    expect(described_class.replay(index).fetch("errors")).to include("id" => "core-json", "error" => "typed data mismatch")
  end

  it "compares expanded XML names while preserving attributes, child order and text" do
    expect(described_class.xml_tree('<a:r xmlns:a="urn:r" b="2" a="1"><x>café</x></a:r>')).to eq(
      described_class.xml_tree('<z:r a="1" b="2" xmlns:z="urn:r"><x>café</x></z:r>'),
    )
    expect(described_class.xml_tree("<r><a/><b/></r>")).not_to eq(described_class.xml_tree("<r><b/><a/></r>"))
    expect(described_class.xml_tree("<r> x </r>")).not_to eq(described_class.xml_tree("<r>x</r>"))
    expect(described_class.xml_tree('<r xmlns="urn:a"/>')).not_to eq(described_class.xml_tree('<r xmlns="urn:b"/>'))
  end

  it "treats CDATA as tree text and checks lexical bytes separately" do
    expect(described_class.xml_tree("<r><![CDATA[x]]></r>")).to eq(described_class.xml_tree("<r>x</r>"))
    entry = { "expected_data" => {}, "expected_output" => "<r><![CDATA[x]]></r>", "comparison" => "bytes" }
    expect(described_class.compare(entry, "data" => {}, "output" => "<r>x</r>")).to eq("output mismatch")
  end

  it "rejects DTD input under the pinned tree profile" do
    expect { described_class.xml_tree('<!DOCTYPE r [<!ENTITY a "x">]><r>&a;</r>') }.to raise_error(ArgumentError)
  end

  it "reports corrupt files and does not rewrite them during check" do
    FileUtils.cp_r("#{directory}/.", temporary)
    File.write(File.join(temporary, "schema.yaml"), "corrupt")
    expect(described_class.check(temporary).fetch("errors")).to include(
      "id" => "package/schema.yaml", "error" => "missing or changed file",
    )
    expect(File.read(File.join(temporary, "schema.yaml"))).to eq("corrupt")
  end

  it "returns nonzero and a case ID for a missing case through the CLI" do
    FileUtils.cp_r("#{directory}/.", temporary)
    index.fetch("cases").shift
    File.write(File.join(temporary, "index.json"), JSON.generate(index))
    output, status = Open3.capture2(RbConfig.ruby, "-Ilib", "scripts/lml/export_conformance.rb", "--check", "--package", temporary)
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output).fetch("errors")).to include("id" => "core-json", "error" => "missing case")
  end
end
