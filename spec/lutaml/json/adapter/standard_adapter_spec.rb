# frozen_string_literal: true

require "spec_helper"
require "lutaml/json/adapter/standard_adapter"

RSpec.describe Lutaml::Json::Adapter::StandardAdapter do
  let(:attributes) { { "name" => "John", "age" => 30 } }

  describe ".parse" do
    # json 3.0 removed create_additions and now raises ArgumentError on any
    # unknown keyword, so the parser must be called without it.
    it "parses without passing removed generator keywords to the json gem" do
      expect(described_class.parse('{"name":"John","age":30}'))
        .to eq(attributes)
    end
  end

  describe "#to_json" do
    subject(:document) { described_class.new(attributes) }

    it "serializes with no options" do
      expect(document.to_json).to eq('{"name":"John","age":30}')
    end

    # :register and :pretty are LutaML's own options. json 2.x ignored unknown
    # options; json 3.0 raises ArgumentError, so they must be stripped before
    # they reach JSON.generate.
    it "strips LutaML options that the json generator does not accept" do
      expect(document.to_json(register: :default_register))
        .to eq('{"name":"John","age":30}')
    end

    it "strips LutaML options when generating pretty output" do
      expect(document.to_json(pretty: true, register: :default_register))
        .to eq(%({\n  "name": "John",\n  "age": 30\n}))
    end

    # An ALLOWLIST and a denylist of LutaML's own option names behave
    # identically for :register and :pretty. Only a key nobody enumerated
    # tells them apart -- and json 3.0 raises on it.
    it "strips a caller option nobody enumerated" do
      expect(document.to_json(some_unknown_option: 1))
        .to eq('{"name":"John","age":30}')
    end

    # The filter is an allowlist, not a passthrough: genuine generator options
    # must still reach JSON.generate.
    it "forwards options the json generator does accept" do
      expect(document.to_json(register: :default_register, space: " "))
        .to eq('{"name": "John","age": 30}')
    end
  end

  describe "nesting inside another JSON.generate call" do
    subject(:document) { described_class.new(attributes) }

    # Ruby's generator hands #to_json a JSON::State, not an options hash.
    # json 3.0 removed JSON::State#[], so reading :pretty off it raises.
    it "serializes when nested in a Hash passed to JSON.generate" do
      expect(JSON.generate({ "doc" => document }))
        .to eq('{"doc":{"name":"John","age":30}}')
    end

    it "serializes when nested in an Array passed to JSON.generate" do
      expect(JSON.generate([document])).to eq('[{"name":"John","age":30}]')
    end

    it "honours a configured JSON::State handed to #to_json directly" do
      # A DEFAULT state renders compact, which is also what a discarded state
      # produces -- so the state has to carry formatting for this to mean
      # anything.
      state = JSON::State.new(indent: "  ", object_nl: "\n", space: " ")
      expect(document.to_json(state))
        .to eq(%({\n  "name": "John",\n  "age": 30\n}))
    end
  end

  describe Lutaml::Json::GeneratorOptions do
    # The derived half of the allowlist reads JSON::State, which Opal's JSON
    # shim does not define. BASE_PERMITTED is what the filter falls back to
    # there, so it has to stand on its own.
    # BASE_PERMITTED is the whole allowlist on Opal, whose JSON shim has no
    # State class for DERIVED_PERMITTED to read. So it has to stand alone
    # against the real generator, not merely be a subset of something larger.
    it "permits only options the running generator actually accepts" do
      rejected = described_class::BASE_PERMITTED.reject do |key|
        JSON.generate({ "a" => 1 }, key => nil)
        true
      rescue ArgumentError => e
        # "unknown keyword" means the generator does not know this option at
        # all. Any other complaint -- a type error about the nil value we
        # passed -- means it knows the option and only dislikes the value.
        !e.message.include?("unknown keyword")
      rescue StandardError
        true
      end

      expect(rejected).to eq([])
    end

    # Opal's JSON shim defines no State class, so DERIVED_PERMITTED is empty
    # there and the whole module must still load. Asserting that
    # BASE_PERMITTED contains some symbols does not exercise the guard; only
    # loading the file with JSON::State absent does.
    it "loads and still permits the base set when JSON::State is absent" do
      hide_const("JSON::State")

      mod = Module.new
      mod.module_eval(
        File.read(File.expand_path("../../../../lib/lutaml/json/generator_options.rb", __dir__)),
      )
      permitted = mod.const_get(:Lutaml).const_get(:Json)
        .const_get(:GeneratorOptions)::PERMITTED

      expect(permitted).to eq(described_class::BASE_PERMITTED)
    end

    it "carries the formatting options pretty output depends on" do
      expect(described_class::BASE_PERMITTED)
        .to include(:indent, :object_nl, :space, :space_before)
    end

    it "rejects a non-Hash options argument" do
      expect(described_class.filter(nil)).to eq({})
    end

    it "treats nil as LutaML options" do
      expect(described_class.lutaml_options?(nil)).to be(true)
    end

    it "treats a Hash as LutaML options" do
      expect(described_class.lutaml_options?({ pretty: true })).to be(true)
    end

    it "does not treat a JSON::State as LutaML options" do
      expect(described_class.lutaml_options?(JSON::State.new)).to be(false)
    end
  end
end
