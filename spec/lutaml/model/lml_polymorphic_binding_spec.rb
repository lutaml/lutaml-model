# frozen_string_literal: true

require "lutaml/model"
require_relative "../../fixtures/lml_serialization_hooks/models"

# A dynamic (default Proc) polymorphic class map is not a finite declaration.
# It is exported only through explicit trusted finite bindings, and the Proc
# is never called.
RSpec.describe "LML polymorphic bindings" do
  let(:fx) { LmlSerializationHookFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:holder_id) { "#{fx::DynamicHolder.name}@default" }
  let(:cases) { { "circle" => fx::Circle, "square" => fx::Square.name } }
  let(:bindings) { { holder_id => { "json" => { "shape" => cases }, "yaml" => { "shape" => cases }, "toml" => { "shape" => cases } } } }

  def refusal_of
    yield
    nil
  rescue Lutaml::Model::Lml::RejectedError => e
    e
  end

  def export(table)
    lml.export_bundle(fx::DynamicHolder, polymorphic_bindings: table)
  end

  def discriminator_of(bundle, format = "json", id = holder_id)
    bundle.models.fetch(id)["mappings"].fetch(format)["rules"].first["discriminator"]
  end

  before { fx.calls.clear }

  describe "without a binding" do
    it "refuses the dynamic map by name instead of exporting empty cases" do
      error = refusal_of { lml.export_bundle(fx::DynamicHolder) }

      expect(error.reason).to eq(:unsupported_mapping)
      expect(error.detail).to include("dynamic").and include("polymorphic_bindings")
    end

    it "never calls the default Proc to find out" do
      refusal_of { lml.export_bundle(fx::DynamicHolder) }

      expect(fx.calls).to be_empty
    end
  end

  describe "with a finite binding" do
    let(:bundle) { export(bindings) }

    it "exports exactly the bound cases, naming each target model" do
      expect(discriminator_of(bundle)).to eq(
        "attribute" => "__kind",
        "cases" => { "circle" => "#{fx::Circle.name}@default", "square" => "#{fx::Square.name}@default" },
      )
    end

    it "includes the bound targets in the graph, so the declaration closes" do
      expect(bundle.models.keys).to include("#{fx::Circle.name}@default", "#{fx::Square.name}@default", "#{fx::Shape.name}@default")
      expect { Lutaml::Model::Lml::DocumentValidator.validate!(bundle.to_h, kind: :bundle) }.not_to raise_error
    end

    it "never executes the default Proc and does not mutate the map" do
      bundle

      expect(fx.calls).to be_empty
      expect(fx::DYNAMIC_MAP.size).to eq(0)
    end

    it "re-exports an equal checksum from fresh classes (cases are static after import)" do
      expect(lml.verify_materialization(bundle).checksum).to eq(bundle.checksum)
    end

    it "keeps the attribute's polymorphic marker out of the document (the rule carries it)" do
      attribute = bundle.models.fetch(holder_id)["attributes"].first

      expect(attribute.keys).not_to include("polymorphic")
    end

    it "lets a derived format (hash, jsonl, yamls) reuse its json twin's binding" do
      expect { export(holder_id => { "json" => { "shape" => cases }, "yaml" => { "shape" => cases }, "toml" => { "shape" => cases } }) }
        .not_to raise_error
    end
  end

  describe "invalid bindings" do
    it "refuses a binding for a format whose dynamic map is left unbound" do
      only_json = { holder_id => { "json" => { "shape" => cases } } }
      error = refusal_of { export(only_json) }

      expect(error.reason).to eq(:unsupported_mapping)
      expect(error.detail).to include("yaml")
    end

    it "refuses unused, unknown-model and unknown-rule bindings" do
      expect(refusal_of { export(bindings.merge("Nope@default" => { "json" => { "x" => cases } })) }.detail).to include("matched no")
      extra = Marshal.load(Marshal.dump(bindings)).tap { |b| b[holder_id]["json"]["ghost"] = cases }
      expect(refusal_of { export(extra) }.detail).to include("ghost")
    end

    it "refuses a binding that targets a static class map" do
      error = refusal_of do
        lml.export_bundle(fx::StaticHolder, polymorphic_bindings: { "#{fx::StaticHolder.name}@default" => { "json" => { "shape" => cases } } })
      end

      expect(error.reason).to eq(:invalid_document)
      expect(error.detail).to include("static")
    end

    it "refuses malformed binding tables" do
      expect(refusal_of { export("bad" => {}) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(holder_id => {}) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(holder_id => { "json" => { "shape" => {} } }) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(holder_id => { "json" => { "shape" => { "" => fx::Circle } } }) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(holder_id => { "json" => { "shape" => { "c" => 5 } } }) }.reason).to eq(:invalid_document)
      expect(refusal_of { export(%w[x]) }.reason).to eq(:invalid_document)
    end

    it "refuses a bound target that cannot be resolved into the graph" do
      broken = { holder_id => { "json" => { "shape" => { "c" => "Nope::Missing" } }, "yaml" => { "shape" => cases },
                                "toml" => { "shape" => cases } } }

      expect(refusal_of { export(broken) }.reason).to eq(:dangling_reference)
    end
  end

  describe "static named polymorphism" do
    it "exports unchanged with no binding and leaves the old cases" do
      bundle = lml.export_bundle(fx::StaticHolder)

      expect(discriminator_of(bundle, "json", "#{fx::StaticHolder.name}@default").fetch("cases")).to eq("circle" => "#{fx::Circle.name}@default")
    end
  end
end
