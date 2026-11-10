# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

# lutaml-model#1033: the opt-in writer for the portable-exact-json-v1 wire
# profile that the TS and Rust codecs read. Native to_json stays
# ruby-native-v1.
RSpec.describe Lutaml::Model::Lml::PortableJson do
  let(:tag_class) do
    Class.new(Lutaml::Model::Serializable) do
      def self.name = "PortableJsonSpec::Tag"
      attribute :name, :string
      attribute :weight, :float
      json do
        map "name", to: :name
        map "weight", to: :weight
      end
    end
  end

  let(:record_class) do
    tag = tag_class
    Class.new(Lutaml::Model::Serializable) do
      def self.name = "PortableJsonSpec::Record"
      attribute :label, :string
      attribute :count, :integer
      attribute :counts, :integer, collection: true
      attribute :price, :decimal
      attribute :ratio, :float
      attribute :open, :boolean
      attribute :meta, :hash
      attribute :tag, tag
      attribute :tags, tag, collection: true
      attribute :note, :string
      json do
        map %w[label lbl], to: :label
        map "count", to: :count
        map "counts", to: :counts
        map "price", to: :price
        map "ratio", to: :ratio
        map "open", to: :open
        map "meta", to: :meta
        map "tag", to: :tag
        map "tags", to: :tags
        map "note", to: :note, render_nil: :as_nil
      end
    end
  end

  def portable(instance)
    JSON.parse(described_class.generate(instance))
  end

  it "names the profile" do
    expect(described_class::PROFILE).to eq("portable-exact-json-v1")
  end

  it "keeps the default to_json output unchanged (ruby-native-v1)" do
    record = record_class.new(label: "a", count: 2**60, price: BigDecimal("1.5"), ratio: 1e20)

    expect(record.to_json).to eq(
      '{"label":"a","count":1152921504606846976,"price":"0.15e1","ratio":1e+20,"note":null}',
    )
  end

  it "writes integers beyond 2**53 as decimal strings, exactly" do
    record = record_class.new(count: 9_007_199_254_740_993, counts: [-7, 0, 2**70])

    expect(described_class.generate(record)).to eq(
      '{"count":"9007199254740993","counts":["-7","0","1180591620717411303424"],"note":null}',
    )
  end

  it "writes decimals as plain strings without an exponent" do
    {
      "1.5" => "1.5", "0.15e1" => "1.5", "-0.0" => "-0.0", "1e-7" => "0.0000001",
      "12345678901234567890.5" => "12345678901234567890.5", "2" => "2.0", "1e20" => "100000000000000000000.0"
    }.each do |input, wire|
      expect(portable(record_class.new(price: BigDecimal(input)))["price"]).to eq(wire)
    end
  end

  it "writes floats in the shared canonical float wire, including negative zero" do
    vectors = JSON.parse(File.read(File.join(__dir__, "../../fixtures/lml_conformance/float_vectors.json")))
    vectors.each do |vector|
      float = [vector.fetch("bits")].pack("H*").unpack1("G")
      expect(portable(record_class.new(ratio: float))["ratio"]).to eq(vector.fetch("wire")), vector["bits"]
    end
    expect(portable(record_class.new(ratio: -0.0))["ratio"]).to eq("-0.0")
  end

  it "keeps strings, booleans, nil, hashes and key order native" do
    record = record_class.new(label: "café", open: false, meta: { "k" => [1, nil] }, count: 3)

    expect(described_class.generate(record)).to eq(
      '{"label":"café","count":"3","open":false,"meta":{"k":[1,null]},"note":null}',
    )
  end

  it "types nested models and collections of models" do
    record = record_class.new(
      tag: tag_class.new(name: "t", weight: 0.5),
      tags: [tag_class.new(weight: 1e-5), tag_class.new(weight: 2.0)],
    )

    expect(portable(record)).to eq(
      "tag" => { "name" => "t", "weight" => "0.5" },
      "tags" => [{ "weight" => "1.0e-5" }, { "weight" => "2.0" }],
      "note" => nil,
    )
  end

  it "is reachable as Lml.portable_json, optionally pretty" do
    record = record_class.new(count: 1)

    expect(Lutaml::Model::Lml.portable_json(record)).to eq('{"count":"1","note":null}')
    expect(Lutaml::Model::Lml.portable_json(record, pretty: true)).to eq(
      "{\n  \"count\": \"1\",\n  \"note\": null\n}",
    )
  end

  it "writes the conformance Record exactly as the portable-exact case expects" do
    require_relative "../../support/lml_conformance"
    record = LmlConformance::Record.new(label: "beyond binary64", count: 9_007_199_254_740_993, enabled: false)
    entry = JSON.parse(File.read(File.join(__dir__, "../../fixtures/lml_conformance/core/index.json")))
      .fetch("cases").find { |c| c["id"] == "core-json-portable-exact" }

    expect(described_class.generate(record)).to eq(entry.fetch("expected_output"))
  end

  describe "refusals" do
    def refusal(&block)
      expect(&block).to raise_error(Lutaml::Model::Lml::RejectedError) { |error| return error }
    end

    it "refuses NaN and Infinity floats, which have no wire form" do
      [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |value|
        error = refusal { described_class.generate(record_class.new(ratio: value)) }
        expect(error.reason).to eq(:not_serializable)
      end
    end

    it "refuses non-finite decimals" do
      error = refusal { described_class.generate(record_class.new(price: BigDecimal("NaN"))) }
      expect(error.reason).to eq(:not_serializable)
    end

    it "refuses a non-Serializable argument" do
      expect(refusal { described_class.generate({}) }.reason).to eq(:not_serializable)
    end

    it "refuses a mapping with custom methods" do
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name = "PortableJsonSpec::Custom"
        attribute :n, :integer
        json { map "n", to: :n, with: { to: :n_to, from: :n_from } }
        def n_to(model, doc) = doc["n"] = model.n
        def n_from(model, value) = model.n = value
      end

      expect(refusal { described_class.generate(klass.new(n: 1)) }.reason).to eq(:unsupported_mapping)
    end

    it "refuses a value type whose native output is a JSON number" do
      numeric = Class.new(Lutaml::Model::Type::Value) do
        def self.name = "PortableJsonSpec::Numeric"
        def self.cast(value, *) = value
        def to_json(*) = 5
      end
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name = "PortableJsonSpec::Holder"
        attribute :n, numeric
        json { map "n", to: :n }
      end

      expect(refusal { described_class.generate(klass.new(n: 5)) }.reason).to eq(:not_serializable)
    end
  end
end
