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

  describe "typed defaults" do
    # Ruby value -> the wire default Lml.export_bundle writes (measured),
    # for every registered builtin the document contract names.
    {
      string: ["s", "s"], token: ["t", "t"], uri: ["http://x/", "http://x/"], hostname: ["h.example", "h.example"],
      boolean: [false, false], integer: [5, 5], decimal: [BigDecimal("1.5"), "1.5"], float: [1.5, "1.5"],
      date: [Date.new(2020, 1, 2), "2020-01-02"], time: [Time.utc(2020, 1, 2, 3, 4, 5), "2020-01-02T03:04:05Z"],
      date_time: [DateTime.new(2020, 1, 2, 3, 4, 5), "2020-01-02T03:04:05+00:00"],
      time_without_date: ["03:04:05", "03:04:05"], duration: ["P1D", "P1D"], qname: ["a:b", "a:b"],
      base64_binary: ["aGk=", "aGk="], hex_binary: ["6869", "6869"], symbol: [:sym, "sym"],
      hash: [{ "a" => 1 }, { "a" => 1 }]
    }.each do |type, (ruby_default, wire)|
      it "accepts the #{type} default the exporter writes (#{wire.inspect})" do
        klass = Class.new(Lutaml::Model::Serializable) do
          def self.name = "TypedDefault"
        end
        klass.attribute :x, type, default: ruby_default
        bundle = lml.export_bundle(klass)

        expect(bundle.to_h["models"].values.first["attributes"].first["default"]).to eq("present" => true, "value" => wire)
        expect { lml::Importer.bundle(bundle.canonical_json) }.not_to raise_error
      end
    end

    # The exporter must never write a default the importer refuses.
    {
      "an integer beyond 2**53 - 1" => [:integer, 2**53, {}],
      "an integer below -(2**53 - 1)" => [:integer, -(2**53), {}],
      "a float collection" => [:float, [1.5, 2.5], { collection: true }],
      "an empty float collection" => [:float, [], { collection: true }],
      "a null float" => [:float, nil, {}],
      "a float inside a hash" => [:hash, { "a" => 1.5 }, {}],
      "a hash collection holding a float" => [:hash, [{ "a" => 1.5 }], { collection: true }],
      "an integer too large for a float" => [:float, 10**400, {}],
      "a float collection of too-large integers" => [:float, [10**400], { collection: true }],
    }.each do |label, (type, default, options)|
      it "refuses to export #{label} as a default" do
        klass = Class.new(Lutaml::Model::Serializable) do
          def self.name = "RefusedDefault"
        end
        klass.attribute :x, type, default: default, **options

        expect { lml.export_bundle(klass) }.to raise_error(lml::RejectedError) { |e|
          expect(e.reason).to eq(:non_serializable_default)
        }
      end
    end

    it "still exports the largest safe integer default and a scalar float" do
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name = "SafeDefaults"
      end
      klass.attribute :a, :integer, default: (2**53) - 1
      klass.attribute :b, :float, default: 2**60

      defaults = lml.export_bundle(klass).to_h["models"].values.first["attributes"].map { |a| a["default"]["value"] }
      expect(defaults).to eq([(2**53) - 1, "1.152921504606847e18"])
      expect { lml::Importer.bundle(lml.export_bundle(klass).canonical_json) }.not_to raise_error
    end

    it "pins one accept and one refuse vector per builtin type in the corpus" do
      names = JSON.parse(File.read(File.join(fixtures, "r2_refusals.json"))).map { |c| c["name"] }
      lml::DocumentValidator::BUILTIN_TYPES.each do |type|
        expect(names).to include("typed_default_ok_#{type}", "typed_default_refused_#{type}")
      end
    end
  end
end
