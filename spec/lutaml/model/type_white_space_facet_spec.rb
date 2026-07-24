# frozen_string_literal: true

require "spec_helper"

RSpec.describe "whiteSpace facet (cast-time normalization)" do
  describe ":collapse mode" do
    before do
      stub_const("CollapsedToken", Class.new(Lutaml::Model::Type::String) do
        white_space :collapse
      end)
      stub_const("Doc", Class.new(Lutaml::Model::Serializable) do
        attribute :token, CollapsedToken
      end)
    end

    it "collapses internal runs and strips edges at cast time" do
      expect(CollapsedToken.cast("  a\t b\n\n c  ")).to eq("a b c")
    end

    it "normalizes the value stored on the model instance" do
      expect(Doc.new(token: "  hello   world  ").token).to eq("hello world")
    end

    it "normalizes values loaded from a serialized document" do
      expect(Doc.from_yaml("token: \"  hello   world  \"\n").token)
        .to eq("hello world")
    end
  end

  describe ":replace mode" do
    before do
      stub_const("ReplacedToken", Class.new(Lutaml::Model::Type::String) do
        white_space :replace
      end)
    end

    it "replaces tab/newline/carriage-return with a single space" do
      expect(ReplacedToken.cast("a\tb\nc\rd")).to eq("a b c d")
    end

    it "keeps existing spaces and edges (no collapse, no strip)" do
      expect(ReplacedToken.cast("  a\tb  ")).to eq("  a b  ")
    end
  end

  describe ":preserve mode" do
    before do
      stub_const("PreservedToken", Class.new(Lutaml::Model::Type::String) do
        white_space :preserve
      end)
    end

    it "leaves the value untouched" do
      expect(PreservedToken.cast("  a\t b  ")).to eq("  a\t b  ")
    end
  end

  describe "declaration guards" do
    it "rejects an unknown mode" do
      expect do
        Class.new(Lutaml::Model::Type::String) { white_space :squash }
      end.to raise_error(ArgumentError, /must be one of/)
    end

    it "rejects white_space on a non-string type at declaration" do
      expect do
        Class.new(Lutaml::Model::Type::Integer) { white_space :collapse }
      end.to raise_error(ArgumentError, /string-derived/)
    end
  end

  describe "inheritance (stricter wins)" do
    before do
      stub_const("ReplaceBase", Class.new(Lutaml::Model::Type::String) do
        white_space :replace
      end)
    end

    it "lets a child tighten to a stricter mode" do
      child = Class.new(ReplaceBase) { white_space :collapse }

      expect(child.facets[:white_space]).to eq(:collapse)
    end

    it "raises when a child loosens the inherited mode" do
      child = Class.new(ReplaceBase) { white_space :preserve }

      expect { child.facets }.to raise_error(ArgumentError, /cannot widen/)
    end

    it "computes each subclass's effective mode independently" do
      strict = Class.new(ReplaceBase) { white_space :collapse }
      plain  = Class.new(ReplaceBase)

      expect(strict.white_space_mode).to eq(:collapse)
      expect(plain.white_space_mode).to eq(:replace)
    end
  end

  describe "memo invalidation when a facet is declared after a cast" do
    it "recomputes the effective mode for a cast-before-declare sequence" do
      cls = Class.new(Lutaml::Model::Type::String)
      expect(cls.cast("a\tb")).to eq("a\tb")

      cls.white_space :collapse

      expect(cls.white_space_mode).to eq(:collapse)
      expect(cls.cast(" a\t b ")).to eq("a b")
    end
  end

  describe "plain :string is unaffected (fast path intact)" do
    before do
      stub_const("Plain", Class.new(Lutaml::Model::Serializable) do
        attribute :s, :string
      end)
    end

    it "does not normalize a plain string attribute" do
      expect(Plain.new(s: "  a   b  ").s).to eq("  a   b  ")
    end

    it "returns the identical object via the EMPTY_OPTIONS fast path" do
      raw = "  a   b  "
      cast = Lutaml::Model::Type::String.cast(
        raw, Lutaml::Model::Type::Value::EMPTY_OPTIONS
      )

      expect(cast).to equal(raw)
    end
  end
end
