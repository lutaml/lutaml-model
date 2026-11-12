# frozen_string_literal: true

require "json"
require "lutaml/model/lml"

RSpec.describe "LML review round-4 probe fixes (encoding, float enums, bundle input)" do
  let(:lml) { Lutaml::Model::Lml }

  def rejection
    yield
    nil
  rescue lml::RejectedError => e
    e
  end

  def model_with(type, name, **options)
    klass = Class.new(Lutaml::Model::Serializable)
    klass.define_singleton_method(:name) { name }
    klass.attribute :v, type, **options
    klass.json { map "v", to: :v }
    klass
  end

  def minimal_model(name)
    { "model" => name, "register" => "default", "attributes" => [], "mappings" => {} }
  end

  describe "non-UTF-8 string defaults and enum values" do
    {
      "ISO-8859-1" => "é".encode("ISO-8859-1"),
      "UTF-16LE" => "a".encode("UTF-16LE"),
      "Shift_JIS" => "表".encode("Shift_JIS"),
      "binary" => "\xff".b,
      "invalid UTF-8" => "\xff",
    }.each do |label, value|
      it "refuses a #{label} default at export" do
        klass = model_with(:string, "R5Default", default: value)

        expect(rejection { lml.export_bundle([klass]) }&.reason).to eq(:non_serializable_default)
      end

      # The model layer cannot declare a UTF-16 or invalid-UTF-8 enum member,
      # so only the other encodings can reach the exporter as enum values.
      next if label.start_with?("UTF-16", "invalid")

      it "refuses a #{label} enum value at export" do
        klass = model_with(:string, "R5Enum", values: [value])

        expect(rejection { lml.export_bundle([klass]) }&.reason).to eq(:non_serializable_default)
      end
    end

    it "refuses a non-UTF-8 string inside a hash default" do
      klass = model_with(:hash, "R5HashDefault", default: { "k" => "\xff".b })

      expect(rejection { lml.export_bundle([klass]) }&.reason).to eq(:non_serializable_default)
    end

    it "still exports ASCII and UTF-8 strings" do
      klass = model_with(:string, "R5Fine", default: "café")

      expect(lml.export_bundle([klass]).canonical_json).to include("café")
    end

    it "refuses a non-UTF-8 string held by a Bundle with RejectedError, not JSON::GeneratorError" do
      document = minimal_model("R5Raw").merge("note" => "\xff".b)

      expect(rejection { lml::Bundle.new(roots: [], models: { "R5Raw@default" => document }) }&.reason)
        .to eq(:invalid_document)
    end
  end

  describe "float enum values" do
    [1.5, 5.0, -0.0, 1e20, 1e-5].each do |value|
      it "round-trips an enum of #{value}" do
        klass = model_with(:float, "R5Float", values: [value])
        bundle = lml.export_bundle([klass])
        classes = lml::Importer.import(bundle.to_h, namespace: Module.new)

        expect(classes.values.first.attributes[:v].options[:values]).to eq([value])
        expect(lml::RoundTrip.verify_materialization(bundle)).to eq(bundle)
      end
    end
  end

  describe "Bundle construction" do
    it "scales linearly with the number of models" do
      build = lambda do |count|
        models = (0...count).to_h { |i| ["R5M#{i}@default", minimal_model("R5M#{i}")] }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        lml::Bundle.new(roots: [], models: models)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end
      build.call(500)
      small = [build.call(1000), build.call(1000)].min
      large = [build.call(4000), build.call(4000)].min

      expect(large / small).to be < 12
    end

    it "still refuses two registers declaring one model" do
      models = { "R5D@default" => minimal_model("R5D"), "R5D@alt" => minimal_model("R5D") }

      expect(rejection { lml::Bundle.new(roots: [], models: models) }&.reason).to eq(:duplicate_id)
    end

    def bundle_with(provenance)
      lml::Bundle.new(roots: [], models: {}, provenance: provenance)
    end

    it "refuses provenance: false like other non-objects" do
      expect(rejection { bundle_with(false) }&.reason).to eq(:invalid_document)
    end

    it "refuses a provenance key in a non-UTF-8-compatible encoding" do
      error = rejection { bundle_with({ "a".encode("UTF-16LE") => 1 }) }

      expect(error&.reason).to eq(:invalid_document)
    end

    [{ a: 1, "a" => 2 }, { 1 => 1, "1" => 2 }, { nil => 1, "" => 2 }].each do |hash|
      it "refuses provenance keys that collide after to_s: #{hash.inspect}" do
        expect(rejection { bundle_with(hash) }&.reason).to eq(:invalid_document)
      end
    end

    it "keeps a lone nil provenance key as the empty string" do
      expect(bundle_with({ nil => 1 }).provenance).to eq({ "" => 1 })
    end
  end

  describe "RoundTrip register diagnosis" do
    let(:leaf) { Class.new(Lutaml::Model::Serializable) { attribute :a, :string } }
    let(:holder) do
      leaf_class = leaf
      Class.new(Lutaml::Model::Serializable) do
        attribute :n, leaf_class
        json { map "n", to: :n }
      end
    end

    before do
      stub_const("R5Leaf", leaf)
      stub_const("R5Holder", holder)
      leaf.json { map "a", to: :a }
    end

    def bundle_in_register(register)
      text = JSON.generate(lml.export_bundle([R5Holder]).to_h)
      JSON.parse(text.gsub("@default", "@#{register}").gsub('"register":"default"', "\"register\":\"#{register}\""))
    end

    it "still reports an unregistered register" do
      error = rejection { lml::RoundTrip.verify_materialization(bundle_in_register("r5zz")) }

      expect(error.message).to include('register "r5zz" is not registered')
    end

    it "does not relabel an unrelated NoMethodError as a register problem" do
      allow(lml::GraphExporter).to receive(:export).and_raise(NoMethodError.new("boom", :boom, receiver: Object.new))

      expect { lml::RoundTrip.verify_materialization(bundle_in_register("r5zz")) }
        .to raise_error(NoMethodError, /boom/)
    end
  end

  describe "importer string scanning" do
    let(:head) { '{"lml_bundle":1,"roots":[],"models":{},"value_types":{},"capabilities":[],"provenance":{' }

    it "accepts a very large escape-heavy string and still sees a duplicate key after it" do
      big = "\"#{'\\"' * 1_000_000}\""
      expect(lml::Importer.bundle("#{head}\"note\":#{big}}}").provenance["note"].size).to eq(1_000_000)

      error = rejection { lml::Importer.bundle("#{head}\"note\":#{big},\"note\":1}}") }
      expect(error.detail).to include("duplicate key")
    end

    it "refuses a huge unterminated escape-heavy string with RejectedError" do
      text = "#{head}\"note\":\"#{'\\"' * 1_000_000}"

      expect(rejection { lml::Importer.bundle(text) }&.reason).to eq(:invalid_document)
    end

    it "refuses a string ending in a lone backslash" do
      expect(rejection { lml::Importer.bundle("#{head}\"note\":\"abc\\") }&.reason).to eq(:invalid_document)
    end
  end

  describe "version-independent detail rendering" do
    it "spells containers without Hash#inspect" do
      expect(lml::RejectedError.show({ "a" => [1, "b"], "c" => nil })).to eq('{"a" => [1, "b"], "c" => nil}')
    end
  end
end
