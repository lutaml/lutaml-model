# frozen_string_literal: true

require "spec_helper"
require_relative "../../../scripts/lml/export_preservation"
require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe LmlPreservation do
  let(:directory) { File.expand_path("../../fixtures/lml_conformance/preservation", __dir__) }
  let(:index) { JSON.parse(File.read(File.join(directory, "index.json"))) }
  let(:cases) { index.fetch("cases").to_h { |entry| [entry.fetch("id"), entry] } }
  let(:temporary) { Dir.mktmpdir("lml-preservation") }

  after { FileUtils.remove_entry(temporary) }

  it "executes all seventeen independent Ruby oracle cases" do
    expect(described_class.check(directory)).to include("expected_count" => 17, "executed_count" => 17, "errors" => [])
    expect(index.fetch("generation")).to eq("preservation-v1")
  end

  it "pins source expectations without modifying the original Ruby specs" do
    expect(index.fetch("source_expectations")).to eq(described_class.source_expectations)
    expect(index.fetch("source_expectations").map { |entry| entry.fetch("path") }).to include(
      "spec/lutaml/model/mixed_content_spec.rb", "spec/lutaml/model/cdata_spec.rb",
      "spec/lutaml/model/collection_spec.rb", "spec/lutaml/model/register_spec.rb"
    )
  end

  it "preserves qualified and unqualified namespace identities in the output tree" do
    entry = cases.fetch("namespace-tree")
    result = described_class.execute(entry, described_class::Namespaces)
    root = REXML::Document.new(result.fetch("output")).root
    expect(root.namespace).to eq("urn:lml:preservation")
    expect(root.elements[1].namespace).to eq("urn:lml:preservation")
    expect(root.elements[2].namespace).to eq("")
    expect(result.fetch("data")).to eq("qualified" => "Q", "plain" => "P")
    model = described_class.schema.fetch("models").fetch("LmlPreservation::Namespaces@default")
    rules = model.fetch("mappings").fetch("xml").fetch("rules")
    expect(rules.map { |rule| rule.fetch("namespace") }).to eq([{ "mode" => "inherit" }, { "mode" => "unqualified" }])
  end

  it "pins namespace bytes independently of tree comparison" do
    entry = cases.fetch("namespace-bytes")
    result = described_class.execute(entry, described_class::Namespaces)
    expect(entry.fetch("comparison")).to eq("bytes")
    expect(result.fetch("output")).to eq(entry.fetch("expected_output"))
    expect(result.fetch("output")).to include("<plain>P</plain>")
  end

  it "captures actual Ruby mixed text and repeated-element order as portable tokens" do
    entry = cases.fetch("mixed-order-tree")
    result = described_class.execute(entry, described_class::Mixed)
    expect(result.fetch("data")).to include("text" => %w[before between after], "em" => %w[one two])
    expect(result.fetch("data").fetch("__lml_content")).to eq([
                                                                { "kind" => "text", "attribute" => "text", "index" => 0 },
                                                                { "kind" => "element", "attribute" => "em", "index" => 0 },
                                                                { "kind" => "text", "attribute" => "text", "index" => 1 },
                                                                { "kind" => "element", "attribute" => "em", "index" => 1 },
                                                                { "kind" => "text", "attribute" => "text", "index" => 2 },
                                                              ])
    expect(result.fetch("output")).to eq(entry.fetch("input"))
  end

  it "preserves ordinary per-instance order instead of grouped attribute order" do
    entry = cases.fetch("ordered-bytes")
    result = described_class.execute(entry, described_class::Ordered)
    expect(result.fetch("output")).to eq("<ordered>\n  <b>one</b>\n  <a>two</a>\n  <b>three</b>\n</ordered>")
    expect(result.fetch("data").fetch("__lml_content").map { |token| token.fetch("attribute") }).to eq(%w[b a b])
  end

  it "preserves CDATA lexical output and decoded content" do
    entry = cases.fetch("cdata-bytes")
    result = described_class.execute(entry, described_class::Cdata)
    expect(result).to eq("data" => { "text" => "a < b & c" }, "output" => entry.fetch("input"))
  end

  it "keeps absent, null, empty and explicit default states distinct" do
    expect(cases.fetch("state-absent").fetch("expected_data").fetch("value")).to eq("state" => "absent", "value" => nil)
    expect(cases.fetch("state-null").fetch("expected_data").fetch("value")).to eq("state" => "present", "value" => nil)
    expect(cases.fetch("state-empty").fetch("expected_data").fetch("value")).to eq("state" => "present", "value" => "")
    expect(cases.fetch("state-absent").fetch("expected_data").fetch("fallback")).to eq("state" => "default", "value" => "default")
    expect(cases.fetch("state-explicit-default").fetch("expected_data").fetch("fallback")).to eq("state" => "present", "value" => "default")
    expect(cases.fetch("state-empty").fetch("expected_data").fetch("items")).to eq("state" => "present", "value" => [])
  end

  it "executes native Ruby state wire expectations without claiming portable YAML I/O" do
    result = described_class.execute(cases.fetch("state-null"), described_class::States)
    expect(JSON.parse(result.fetch("output"))).to eq("value" => nil, "items" => [])
    expect(index.fetch("wire_profile")).to eq("ruby-native")
    expect(index.fetch("data_profile")).to eq("exact-values-decimal-v1")
    expect(cases.values.map { |entry| entry.fetch("format") }.uniq.sort).to eq(%w[json xml])
  end

  it "preserves cardinality bounds and both negative boundary results" do
    expect(cases.fetch("cardinality-valid").fetch("expected_data")).to eq("items" => %w[one two])
    %w[cardinality-invalid cardinality-missing].each do |id|
      result = described_class.execute(cases.fetch(id), described_class::Bounded)
      expect(result.fetch("error")).to include(
        "reason" => "invalid_document", "model_id" => "LmlPreservation::Bounded@default",
        "ruby_errors" => ["Lutaml::Model::CollectionCountOutOfRangeError"]
      )
    end
  end

  it "preserves typed integer and boolean enum declarations and exact normalized values" do
    model = described_class.schema.fetch("models").fetch("LmlPreservation::TypedEnum@default")
    expect(model.fetch("attributes").map { |field| field.fetch("values") }).to eq([[1, 2], [true, false]])
    expect(cases.fetch("typed-enum-valid").fetch("expected_data")).to eq("number" => "2", "flag" => false)
    expect(described_class.execute(cases.fetch("typed-enum-invalid"), described_class::TypedEnum).fetch("error")).to include(
      "reason" => "invalid_document", "ruby_errors" => ["Lutaml::Model::InvalidValueError"],
    )
  end

  it "executes an explicit imported context without changing the global default register" do
    original = Lutaml::Model::Config.default_register
    result = described_class.execute(cases.fetch("imported-context"), described_class::Imported)
    expect(result.fetch("data")).to eq("name" => "contextual")
    expect(result.fetch("output")).to eq('{"name":"contextual"}')
    expect(described_class::Imported.attributes(:default)).not_to have_key(:name)
    expect(described_class::Imported.attributes(:oracle)).to have_key(:name)
    expect(Lutaml::Model::Config.default_register).to eq(original)
  end

  it "pins equivalent JSON and safely parsed YAML schemas and actual payload digests" do
    expect(YAML.safe_load_file(File.join(directory, "schema.yaml"), aliases: false)).to eq(
      JSON.parse(File.read(File.join(directory, "schema.json"))),
    )
    manifest = JSON.parse(File.read(File.join(directory, "manifest.json")))
    manifest.fetch("files").each do |entry|
      expect(described_class.digest(File.binread(File.join(directory, entry.fetch("path"))))).to eq(entry.fetch("sha256"))
    end
    described_class.files.each { |path, bytes| expect(File.binread(File.join(directory, path))).to eq(bytes.b) }
  end

  it "fails a missing case by ID" do
    FileUtils.cp_r("#{directory}/.", temporary)
    index.fetch("cases").shift
    File.write(File.join(temporary, "index.json"), JSON.generate(index))
    expect(described_class.check(temporary).fetch("errors")).to include("id" => "namespace-tree", "error" => "missing case")
  end

  it "fails unknown, duplicate and changed cases by ID" do
    FileUtils.cp_r("#{directory}/.", temporary)
    index.fetch("cases") << cases.fetch("namespace-tree").merge("id" => "unknown")
    index.fetch("cases") << cases.fetch("namespace-tree").dup
    cases.fetch("mixed-order-tree")["input"] = "<mixed/>"
    File.write(File.join(temporary, "index.json"), JSON.generate(index))
    expect(described_class.check(temporary).fetch("errors")).to include(
      { "id" => "unknown", "error" => "unknown case" },
      { "id" => "namespace-tree", "error" => "duplicate case" },
      { "id" => "mixed-order-tree", "error" => "changed case" },
    )
  end

  it "detects byte changes even when the XML tree remains equivalent" do
    entry = cases.fetch("namespace-bytes")
    result = { "data" => entry.fetch("expected_data"), "output" => entry.fetch("expected_output").gsub("p:", "z:").sub("xmlns:p", "xmlns:z") }
    expect(described_class.xml_tree(result.fetch("output"))).to eq(described_class.xml_tree(entry.fetch("expected_output")))
    expect(described_class.compare(entry, result)).to eq("output mismatch")
  end

  it "detects changed ordering and values through the tree comparator" do
    entry = cases.fetch("mixed-order-tree")
    result = { "data" => entry.fetch("expected_data"), "output" => "<mixed>before<em>two</em>between<em>one</em>after</mixed>" }
    expect(described_class.compare(entry, result)).to eq("output mismatch")
    result["output"] = entry.fetch("expected_output").sub("before", "changed")
    expect(described_class.compare(entry, result)).to eq("output mismatch")
  end

  it "returns nonzero with the changed case ID through the read-only CLI" do
    FileUtils.cp_r("#{directory}/.", temporary)
    cases.fetch("cdata-bytes")["expected_output"] = "<cdata>a &lt; b &amp; c</cdata>"
    bytes = JSON.generate(index)
    File.write(File.join(temporary, "index.json"), bytes)
    output, status = Open3.capture2(RbConfig.ruby, "scripts/lml/export_preservation.rb", "--check", "--package", temporary)
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output).fetch("errors")).to include("id" => "cdata-bytes", "error" => "changed case")
    expect(File.read(File.join(temporary, "index.json"))).to eq(bytes)
  end
end
