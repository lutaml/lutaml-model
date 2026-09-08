# frozen_string_literal: true

require "spec_helper"
require "multi_json"
require "lutaml/json/adapter/multi_json_adapter"

RSpec.describe Lutaml::Json::Adapter::MultiJsonAdapter do
  let(:attributes) { { "name" => "John", "age" => 30 } }

  describe ".parse" do
    # multi_json 1.21.1 sends create_additions and quirks_mode on every load
    # and json 3.0 removed both, so the json_gem backend raises. The adapter
    # detects those options and goes straight to JSON.parse instead.
    it "parses despite multi_json's removed load defaults" do
      expect(described_class.parse('{"name":"John","age":30}')).to eq(attributes)
    end
  end

  describe "#to_json" do
    subject(:document) { described_class.new(attributes) }

    it "strips LutaML options the engine would reject" do
      expect(document.to_json(register: :default_register))
        .to eq('{"name":"John","age":30}')
    end

    # MultiJson dispatches to whichever backend is active and each has its own
    # option names. Filtering through the stdlib JSON allowlist would discard
    # them, so only LutaML's own keys are stripped.
    it "forwards a backend-specific option the stdlib generator does not know" do
      require "oj"
      previous = MultiJson.adapter
      MultiJson.use(:oj)
      doc = described_class.new({ "kept" => 1, "dropped" => nil })

      expect(doc.to_json(omit_nil: true, register: :r)).to eq('{"kept":1}')
    ensure
      MultiJson.use(previous) if previous
    end

    # LutaML threads more than :register through -- a Collection adds
    # `collection: true`. Every one of them has to be stripped, not just the
    # one the other examples happen to pass.
    it "strips every LutaML-internal key, not only :register" do
      expect(document.to_json(collection: true, _adapter_override: true,
                              register: :r))
        .to eq('{"name":"John","age":30}')
    end

    # Ruby's generator passes a JSON::State when the document is nested.
    it "inherits the outer indent when nested in a pretty document" do
      expect(JSON.pretty_generate({ "doc" => document }))
        .to eq(%({\n  "doc": {\n    "name": "John",\n    "age": 30\n  }\n}))
    end
  end
end
