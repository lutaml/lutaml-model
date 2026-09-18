# frozen_string_literal: true

require "spec_helper"

# lutaml-model#550: options passed to `from_*` / `to_*` flow to custom
# methods that declare the extra context parameter (arity-aware; the
# historical signatures keep working).
RSpec.describe "Custom method context forwarding" do
  let(:model_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      def name_from(model, value, ctx = nil)
        model.name = "#{value} (#{ctx ? ctx[:schema] : 'none'})"
      end

      def name_to(model, hash, ctx = nil)
        hash["name"] = "#{model.name} <#{ctx ? ctx[:schema] : 'none'}>"
      end

      key_value do
        map "name", to: :name,
                    with: { from: :name_from, to: :name_to }
      end
    end
  end

  it "passes context to custom methods on parse when accepted" do
    parsed = model_class.from_yaml({ "name" => "Alpine" }.to_yaml,
                                   context: { schema: "ISO" })
    expect(parsed.name).to eq("Alpine (ISO)")
  end

  it "passes context to custom methods on serialize when accepted" do
    instance = model_class.from_yaml({ "name" => "Alpine" }.to_yaml)
    out = instance.to_yaml(context: { schema: "ISO" })
    expect(out).to include("Alpine (none) <ISO>")
  end

  it "keeps two-parameter custom methods working without context" do
    parsed = model_class.from_yaml({ "name" => "Alpine" }.to_yaml)
    expect(parsed.name).to eq("Alpine (none)")

    out = parsed.to_yaml
    expect(out).to include("Alpine (none) <none>")
  end

  it "forwards context to with-lambdas of exact arity 2" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :code, :string

      key_value do
        map "code", to: :code,
                    with: { from: ->(value, ctx) { "#{value}-#{ctx[:rev]}" } }
      end
    end

    parsed = klass.from_yaml({ "code" => "A1" }.to_yaml,
                              context: { rev: 7 })
    expect(parsed.code).to eq("A1-7")
  end
end
