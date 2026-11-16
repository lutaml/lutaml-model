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
    rebuilt = result.fetch("cases")
    expect(rebuilt.map { |entry| entry.key?("refused") }).to all(be(false))
    expect(rebuilt.map { |entry| entry.fetch("id") }).to contain_exactly(
      "v3-mi-mixed", "v3-math-nested", "v4-mi-mixed", "v4-math-nested"
    )
    rebuilt.each do |entry|
      graph = manifest.fetch("graphs").fetch(entry.fetch("id"))
      expect(entry.fetch("checksum")).to eq(graph.fetch("checksum"))
      expect(entry.fetch("model_count")).to eq(graph.fetch("source_references").size)
      source = oracles.find { |oracle| oracle.fetch("id") == entry.fetch("id") }
      expect(entry.fetch("actual")).to eq(source.fetch("expected"))
    end
    expect(rebuilt.to_h { |entry| [entry.fetch("id"), entry.fetch("model_count")] }).to eq(
      "v3-mi-mixed" => 3, "v3-math-nested" => 194, "v4-mi-mixed" => 3, "v4-math-nested" => 195,
    )
  end

  it "rejects modified oracle bytes before reconstruction" do
    FileUtils.cp_r("#{package}/.", temporary)
    File.write(File.join(temporary, "oracle.json"), '{"cases":[]}')
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", runner, temporary, File.join(temporary, "result.json"))
    expect(status.success?).to be(false)
    expect(stderr).to include("payload digest mismatch: oracle.json")
  end
end
