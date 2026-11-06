# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# lutaml-model#1033: Ruby owns the cross-language LML corpora. The TS and Rust
# ports copy these goldens byte for byte, so a Ruby validator or float-wire
# change must fail here (regenerate the goldens deliberately, then re-copy).
RSpec.describe "LML shared conformance corpora" do
  let(:fixtures) { File.expand_path("../../fixtures/lml_conformance", __dir__) }
  let(:lib) { File.expand_path("../../../lib", __dir__) }
  let(:lml) { Lutaml::Model::Lml }

  def regenerate(generator, out)
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", lib, File.join(fixtures, generator), out)
    expect(status).to be_success, stderr
    File.binread(out)
  end

  describe "r2_refusals.json" do
    it "is byte-identical to a fresh regeneration" do
      Dir.mktmpdir do |dir|
        fresh = regenerate("r2_refusals.generator.rb", File.join(dir, "r2.json"))
        expect(fresh).to eq(File.binread(File.join(fixtures, "r2_refusals.json")))
      end
    end
  end

  describe "float_vectors.json" do
    let(:vectors) { JSON.parse(File.read(File.join(fixtures, "float_vectors.json"))) }

    it "is byte-identical to a fresh regeneration" do
      Dir.mktmpdir do |dir|
        fresh = regenerate("float_vectors.generator.rb", File.join(dir, "fv.json"))
        expect(fresh).to eq(File.binread(File.join(fixtures, "float_vectors.json")))
      end
    end

    it "covers at least 2000 distinct doubles and the notation boundaries" do
      wires = vectors.to_h { |v| [v["bits"], v["wire"]] }
      expect(wires.size).to be >= 2000
      expect(wires.values_at("430c6bf526340000", "43105cf3917d6f0b", "43118b54f22aeb00", "8000000000000000"))
        .to eq(["1.0e15", "1151450203773890.8", "1.234567890123456e15", "-0.0"])
    end

    it "accepts every wire string as a canonical float and round-trips the bits" do
      bad = vectors.reject do |v|
        value = [v["bits"].to_i(16)].pack("Q>").unpack1("G")
        lml::DocumentValidator.canonical_float?(v["wire"]) &&
          [Float(v["wire"])].pack("G") == [value].pack("G")
      end
      expect(bad).to be_empty
    end
  end
end
