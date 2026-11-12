# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# lutaml-model#1033: ruby_portable_interop.json is the Lml.portable_json output
# the generated TS and Rust JSON codecs must read and write back identically.
# The TS and Rust repos copy it byte for byte; a Ruby writer change fails here.
RSpec.describe "LML Ruby portable_json interop fixture" do
  let(:fixtures) { File.expand_path("../../fixtures/lml_conformance", __dir__) }
  let(:lib) { File.expand_path("../../../lib", __dir__) }
  let(:path) { File.join(fixtures, "ruby_portable_interop.json") }
  let(:fixture) { JSON.parse(File.read(path)) }

  it "is byte-identical to a fresh regeneration" do
    Dir.mktmpdir do |dir|
      out = File.join(dir, "interop.json")
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, "-I", lib, File.join(fixtures, "ruby_portable_interop.generator.rb"), out
      )
      expect(status).to be_success, stderr
      expect(File.binread(out)).to eq(File.binread(path))
    end
  end

  it "pins the value shapes the ports must reproduce" do
    first = JSON.parse(fixture["outputs"][0])
    expect(fixture["outputs"].size).to eq(3)
    expect(fixture["bundle"]["models"].keys).to contain_exactly("Interop::Rec@default", "Interop::Tag@default")
    expect(first["count"]).to eq("9007199254740993")
    expect(first["counts"]).to eq(["-7", "0", (2**70).to_s])
    expect(first["tag"]["weight"]).to eq("-0.0")
  end
end
