# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/lml/graph_exporter"
require_relative "../../support/lml_graph_fixtures"

RSpec.describe Lutaml::Model::Lml::GraphExporter do
  let(:fx) { LmlGraphFixtures }
  let(:graph) { described_class }

  def id(klass, register = "default")
    "#{klass.name}@#{register}"
  end

  def export(roots, **opts)
    graph.export(roots, projector: fx.projector, **opts)
  end

  it "exports a self-referential model once and terminates" do
    calls = []
    bundle = graph.export([fx::Node], projector: fx.projector({}, calls))

    expect(bundle.models.keys).to eq([id(fx::Node)])
    expect(bundle.roots).to eq([id(fx::Node)])
    expect(calls.size).to eq(1)
  end

  it "closes mutual cycles from either root and yields identical bundles" do
    from_left = export([fx::Left])
    from_right = export([fx::Right])

    expect(from_left.models.keys).to eq([id(fx::Left), id(fx::Right)].sort)
    expect(from_left.models).to eq(from_right.models)
    expect(from_left.roots).not_to eq(from_right.roots)
  end

  it "follows discriminator targets" do
    bundle = export([fx::Shape])
    expect(bundle.models.keys).to eq([fx::Circle, fx::Shape, fx::Square].map { |k| id(k) }.sort)
  end

  it "hoists value types to the bundle and requires them to exist" do
    bundle = export([fx::Holder])
    expect(bundle.value_types.keys).to eq(["Size"])
    expect(bundle.models[id(fx::Holder)]).not_to have_key("value_types")
  end

  it "sorts roots and capabilities and ignores root order and duplicates" do
    a = export([fx::Node, fx::Leaf, fx::Node])
    b = export([fx::Leaf, fx::Node])

    expect(a.roots).to eq([id(fx::Leaf), id(fx::Node)])
    expect(a.capabilities).to eq(["xml"])
    expect(a.canonical_json).to eq(b.canonical_json)
    expect(a.checksum).to eq(b.checksum)
  end

  it "excludes provenance from the checksum but keeps it in the document" do
    plain = export([fx::Leaf])
    tagged = export([fx::Leaf], provenance: { "source_revision" => "abc" })

    expect(tagged.checksum).to eq(plain.checksum)
    expect(tagged.to_h["provenance"]).to eq("source_revision" => "abc")
    expect(tagged.canonical_json).not_to eq(plain.canonical_json)
    expect(plain.checksum).to match(/\Asha256:\h{64}\z/)
  end

  it "changes the checksum when a model definition changes" do
    changed = graph.export(
      [fx::Leaf],
      projector: fx.projector(id(fx::Leaf) => fx.document(fx::Leaf, "default", [fx.attribute("x", { "kind" => "builtin", "name" => "string" })])),
    )
    expect(changed.checksum).not_to eq(export([fx::Leaf]).checksum)
    expect(changed.model_checksum(id(fx::Leaf))).to match(/\Asha256:\h{64}\z/)
  end

  it "emits compact key-sorted JSON without escaping slashes or non-ASCII" do
    doc = fx.document(fx::Leaf, "default", [], "zeta" => "a/é", "alpha" => 1)
    bundle = graph.export([fx::Leaf], projector: fx.projector(id(fx::Leaf) => doc))
    json = bundle.canonical_json

    expect(json).to include('"alpha":1,"attributes":[],"lml":2')
    expect(json).to include('"zeta":"a/é"')
    expect(json).not_to match(/\s|\n\z/)
  end

  it "is immutable and unaffected by later mutation of projector output" do
    doc = fx.document(fx::Leaf, "default")
    bundle = graph.export([fx::Leaf], projector: fx.projector(id(fx::Leaf) => doc))
    before = bundle.checksum
    doc["attributes"] << { "name" => "late" }

    expect(bundle.checksum).to eq(before)
    expect(bundle.models).to be_frozen
    expect { bundle.models[id(fx::Leaf)]["lml"] = 3 }.to raise_error(FrozenError)
  end

  describe "register contexts" do
    it "keys the same class separately per register without contamination" do
      alt = export([fx::Left], register: :alt)
      default = export([fx::Left])

      expect(alt.models.keys).to eq([id(fx::Left, "alt"), id(fx::Right, "alt")].sort)
      expect(alt.models[id(fx::Left, "alt")]["attributes"][0]["type"]["id"]).to eq(id(fx::Right, "alt"))
      expect(default.models.keys).to eq([id(fx::Left), id(fx::Right)].sort)
      expect(alt.checksum).not_to eq(default.checksum)
    end

    it "accepts [class, register] roots and class default registers" do
      fx::Leaf.define_singleton_method(:lutaml_default_register) { :mml_v2 }
      begin
        expect(export([fx::Leaf]).roots).to eq([id(fx::Leaf, "mml_v2")])
        expect(export([[fx::Leaf, "x"]]).roots).to eq([id(fx::Leaf, "x")])
      ensure
        fx::Leaf.singleton_class.send(:remove_method, :lutaml_default_register)
      end
    end

    it "keeps the original schema ID when the register substitutes a class" do
      resolver = lambda { |name, register|
        name == fx::Right.name && register == "alt" ? fx::Substitute : Object.const_get(name)
      }
      projector = fx.projector(
        id(fx::Substitute, "alt") => fx.document(fx::Substitute, "alt"),
      )
      bundle = graph.export([fx::Left], register: "alt", projector: projector, resolver: resolver)

      expect(bundle.models.keys).to include(id(fx::Right, "alt"))
      expect(bundle.models[id(fx::Right, "alt")]["model"]).to eq(fx::Right.name)
      expect(bundle.models.keys).not_to include(id(fx::Substitute, "alt"))
    end

    it "rejects non-portable register names" do
      expect { export([fx::Leaf], register: "bad register") }
        .to raise_error(Lutaml::Model::Lml::RejectedError) { |e| expect(e.reason).to eq(:invalid_document) }
    end
  end

  describe "rejections" do
    def reason_of
      yield
      nil
    rescue Lutaml::Model::Lml::RejectedError => e
      e.reason
    end

    it "rejects anonymous classes" do
      expect(reason_of { export([Class.new]) }).to eq(:invalid_document)
    end

    it "rejects an unresolvable target as dangling" do
      projector = fx.projector(
        id(fx::Leaf) => fx.document(fx::Leaf, "default", [fx.attribute("m", fx.model_ref("Nope::Missing@default"))]),
      )
      expect(reason_of { graph.export([fx::Leaf], projector: projector) }).to eq(:dangling_reference)
    end

    it "rejects a value type that is never defined" do
      projector = fx.projector(
        id(fx::Leaf) => fx.document(fx::Leaf, "default", [fx.attribute("v", { "kind" => "value", "id" => "Ghost" })]),
      )
      expect(reason_of { graph.export([fx::Leaf], projector: projector) }).to eq(:dangling_reference)
    end

    it "rejects one ID defined differently by two classes" do
      twin = Class.new
      stub_const("LmlGraphFixtures::Twin", twin)
      allow(twin).to receive(:name).and_return(fx::Leaf.name)
      projector = lambda { |klass, register|
        extra = klass.equal?(twin) ? [fx.attribute("z", { "kind" => "builtin", "name" => "string" })] : []
        fx.document(fx::Leaf, register, extra)
      }
      expect(reason_of { graph.export([fx::Leaf, twin], projector: projector) }).to eq(:duplicate_id)
    end

    it "accepts two classes projecting an identical definition" do
      twin = Class.new
      allow(twin).to receive(:name).and_return(fx::Leaf.name)
      projector = ->(_klass, register) { fx.document(fx::Leaf, register) }
      expect(graph.export([fx::Leaf, twin], projector: projector).models.size).to eq(1)
    end

    it "rejects a document whose identity disagrees with its ID" do
      projector = fx.projector(id(fx::Leaf) => fx.document(fx::Node, "default"))
      expect(reason_of { graph.export([fx::Leaf], projector: projector) }).to eq(:invalid_document)
    end

    it "rejects a projector result that is not a Hash" do
      expect(reason_of { graph.export([fx::Leaf], projector: ->(*) { [] }) }).to eq(:invalid_document)
    end

    it "does not return a partial bundle when a nested target fails" do
      projector = lambda { |klass, register|
        raise Lutaml::Model::Lml::RejectedError.new(:custom_initialize, klass) if klass == fx::Right

        fx.projector.call(klass, register)
      }
      expect(reason_of { graph.export([fx::Left], projector: projector) }).to eq(:custom_initialize)
    end
  end
end
