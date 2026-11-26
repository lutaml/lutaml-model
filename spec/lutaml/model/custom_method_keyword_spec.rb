# frozen_string_literal: true

require "spec_helper"

# A `from` callback with NO positional parameter and only keywords
# (`def from(**)`, `def from(model:, value:)`) is invoked with the keywords it
# declares (model:, value:, context:). Every method with a positional
# parameter, every lambda and every nil input behave exactly as before.
RSpec.describe "Keyword-only custom `from` callbacks" do
  def build(&callback_definition)
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :seen, :string, collection: true

      class_eval(&callback_definition)

      key_value do
        map "name", with: { from: :name_from, to: :name_to }
      end

      def name_to(model, doc)
        doc["name"] = model.name
      end
    end
  end

  def parse(klass, value = "x", **options)
    klass.from_yaml({ "name" => value }.to_yaml, **options)
  end

  describe "the keyword-only forms" do
    it "calls `(**)` with model:, value: and context: and honors its no-op" do
      klass = build do
        def name_from(**)
          nil
        end
      end

      expect(parse(klass).name).to be_nil
    end

    it "hands all three keywords to `(**options)`" do
      klass = build do
        def name_from(**options)
          options[:model].name = "#{options[:value]}|#{options[:context]&.fetch(:tag, nil)}|#{options.keys.sort.join(',')}"
        end
      end

      expect(parse(klass, "v", context: { tag: "T" }).name).to eq("v|T|context,model,value")
    end

    it "passes only the keywords an explicit signature names" do
      klass = build do
        def name_from(model:, value:)
          model.name = "kw:#{value}"
        end
      end

      expect(parse(klass, "v").name).to eq("kw:v")
    end

    it "accepts optional keywords and a context keyword" do
      klass = build do
        def name_from(model:, value: nil, context: nil)
          model.name = "#{value}@#{context&.fetch(:schema, nil)}"
        end
      end

      expect(parse(klass, "v", context: { schema: "ISO" }).name).to eq("v@ISO")
    end

    it "keeps a required keyword it cannot supply as the historical ArgumentError" do
      klass = build do
        def name_from(model:, other:); end
      end

      expect { parse(klass) }.to raise_error(StandardError) { |e| expect(e.message).to match(/argument|input format/i) }
    end
  end

  describe "preservation of the existing forms" do
    it "keeps the two positional parameter form" do
      klass = build do
        def name_from(model, value)
          model.name = "two:#{value}"
        end
      end

      expect(parse(klass, "v").name).to eq("two:v")
    end

    it "keeps the three positional parameter (context) form" do
      klass = build do
        def name_from(model, value, ctx = nil)
          model.name = "three:#{value}:#{ctx ? ctx[:schema] : 'none'}"
        end
      end

      expect(parse(klass, "v", context: { schema: "ISO" }).name).to eq("three:v:ISO")
      expect(parse(klass, "v").name).to eq("three:v:none")
    end

    it "keeps lambda callables, including the exact-arity-2 context form" do
      one = Class.new(Lutaml::Model::Serializable) do
        attribute :code, :string
        key_value { map "code", to: :code, with: { from: ->(value) { "L#{value}" } } }
      end
      two = Class.new(Lutaml::Model::Serializable) do
        attribute :code, :string
        key_value { map "code", to: :code, with: { from: ->(value, ctx) { "#{value}-#{ctx[:rev]}" } } }
      end

      expect(one.from_yaml({ "code" => "A" }.to_yaml).code).to eq("LA")
      expect(two.from_yaml({ "code" => "A" }.to_yaml, context: { rev: 7 }).code).to eq("A-7")
    end

    it "does not call any callback for a nil input" do
      calls = []
      klass = build do
        define_method(:name_from) { |**| calls << :called }
      end
      klass.from_yaml({ "name" => nil }.to_yaml)

      expect(calls).to be_empty
    end
  end

  describe "the keyword classification" do
    let(:rule) { Lutaml::Model::MappingRule }

    it "classifies parameter lists" do
      expect(rule.keyword_callback_arguments([%i[keyrest **]])).to eq(%i[model value context])
      expect(rule.keyword_callback_arguments([%i[keyreq model], %i[keyreq value]])).to eq(%i[model value])
      expect(rule.keyword_callback_arguments([%i[req model], %i[req value]])).to be_nil
      expect(rule.keyword_callback_arguments([%i[req model], %i[key flag]])).to be_nil
      expect(rule.keyword_callback_arguments([%i[keyreq nope]])).to be_nil
      expect(rule.keyword_callback_arguments([%i[key unrelated]])).to be_nil
      expect(rule.keyword_callback_arguments([])).to be_nil
    end
  end
end
