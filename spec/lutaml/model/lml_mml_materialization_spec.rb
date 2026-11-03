# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "Fresh-process real MML materialization" do
  let(:package) { File.expand_path("../../fixtures/lml_mml", __dir__) }
  let(:runner) { File.expand_path("../../fixtures/lml_mml_materialization/replay.rb", __dir__) }
  let(:manifest) { JSON.parse(File.read(File.join(package, "manifest.json"))) }
  let(:oracles) { JSON.parse(File.read(File.join(package, "oracle.json"))).fetch("cases") }
  let(:temporary) { Dir.mktmpdir("lml-mml-materialization") }

  after { FileUtils.remove_entry(temporary) }

  def run_replay
    result_path = File.join(temporary, "result.json")
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", runner, package, result_path)
    expect(status.success?).to be(true), stderr
    JSON.parse(File.read(result_path))
  end

  it "reconstructs every exported mml graph in a fresh process without the source constants" do
    result = run_replay
    expect(result.fetch("source_constants_loaded")).to be(false)
    expect(result.fetch("cases").map { |entry| entry.fetch("id") }).to match_array(oracles.map { |entry| entry.fetch("id") })
    rebuilt = result.fetch("cases").reject { |entry| entry.key?("refused") }
    expect(rebuilt.map { |entry| entry.fetch("id") }).to contain_exactly("v3-mi-mixed", "v4-mi-mixed")
    rebuilt.each do |entry|
      graph = manifest.fetch("graphs").fetch(entry.fetch("id"))
      expect(entry.fetch("checksum")).to eq(graph.fetch("checksum"))
      expect(entry.fetch("model_count")).to eq(graph.fetch("source_references").size)
      source = oracles.find { |oracle| oracle.fetch("id") == entry.fetch("id") }
      expect(entry.fetch("actual")).to eq(source.fetch("expected"))
    end
    expect(rebuilt.map { |entry| entry.fetch("model_count") }).to eq([3, 3])
  end

  it "reports the Math graphs as refused by name (float contract) instead of reconstructing a pruned graph" do
    refused = run_replay.fetch("cases").select { |entry| entry.key?("refused") }
    expect(refused.to_h { |entry| [entry.fetch("id"), entry.fetch("refused")] }).to eq(
      manifest.fetch("graphs").slice("v3-math-nested", "v4-math-nested").transform_values { |graph| graph.fetch("refusal") },
    )
    expect(refused.map { |entry| entry.fetch("refused").fetch("reason") }).to eq(%w[unsupported_type unsupported_type])
  end

  it "rejects modified oracle bytes before reconstruction" do
    FileUtils.cp_r("#{package}/.", temporary)
    File.write(File.join(temporary, "oracle.json"), '{"cases":[]}')
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", runner, temporary, File.join(temporary, "result.json"))
    expect(status.success?).to be(false)
    expect(stderr).to include("payload digest mismatch: oracle.json")
  end
end
