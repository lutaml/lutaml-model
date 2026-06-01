# frozen_string_literal: true

require "spec_helper"
require "liquid"

RSpec.describe Lutaml::Model::Liquid::IndexedAccess do
  describe "integration with auto-generated drops" do
    before do
      stub_const("IndexedSpec::Item", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :value, :string
      end)

      stub_const("IndexedSpec::ItemCollection", Class.new(Lutaml::Model::Serializable) do
        include Lutaml::Model::Liquid::IndexedAccess

        attribute :items, IndexedSpec::Item, collection: true

        def [](key)
          case key
          when Integer then items[key]
          when String then items.find { |i| i.name == key }
          end
        end
      end)
    end

    let(:collection) do
      IndexedSpec::ItemCollection.new(
        items: [
          IndexedSpec::Item.new(name: "alpha", value: "A"),
          IndexedSpec::Item.new(name: "beta", value: "B"),
          IndexedSpec::Item.new(name: "gamma", value: "C"),
        ],
      )
    end

    let(:drop) { collection.to_liquid }

    describe "#liquid_method_missing" do
      it "resolves string key via liquid_fetch" do
        result = drop["alpha"]
        expect(result).to be_a(Liquid::Drop)
        expect(result.name).to eq("alpha")
        expect(result.value).to eq("A")
      end

      it "resolves integer index via liquid_fetch" do
        result = drop[0]
        expect(result).to be_a(Liquid::Drop)
        expect(result.name).to eq("alpha")
      end

      it "returns nil for unknown key" do
        result = drop["nonexistent"]
        expect(result).to be_nil
      end

      it "returns nil for out-of-bounds index" do
        result = drop[99]
        expect(result).to be_nil
      end
    end

    describe "Liquid template rendering" do
      it "resolves bracket access in templates" do
        template = Liquid::Template.parse("{{ collection['beta'].value }}")
        result = template.render("collection" => drop)
        expect(result).to eq("B")
      end

      it "resolves integer bracket access in templates" do
        template = Liquid::Template.parse("{{ collection[2].name }}")
        result = template.render("collection" => drop)
        expect(result).to eq("gamma")
      end

      it "renders empty string for unknown key" do
        template = Liquid::Template.parse("{{ collection['missing'].name }}")
        result = template.render("collection" => drop)
        expect(result).to eq("")
      end
    end

    describe "coexistence with declared attribute methods" do
      it "still exposes declared attributes normally" do
        expect(drop.items).to be_a(Array)
        expect(drop.items.size).to eq(3)
        expect(drop.items[0].name).to eq("alpha")
      end

      it "prefers declared methods over indexed access" do
        # 'items' is a declared attribute, so invoke_drop('items') calls
        # the generated method, not liquid_fetch
        result = drop.items
        expect(result).to be_a(Array)
      end
    end
  end

  describe "objects without IndexedAccess" do
    before do
      stub_const("PlainSpec::Model", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
      end)
    end

    let(:instance) { PlainSpec::Model.new(name: "test") }
    let(:drop) { instance.to_liquid }

    it "does not attempt bracket access on non-indexed objects" do
      result = drop["anything"]
      expect(result).to be_nil
    end

    it "still exposes declared attributes" do
      expect(drop.name).to eq("test")
    end
  end

  describe "IndexedAccess module" do
    it "provides liquid_fetch that delegates to []" do
      klass = Class.new do
        include Lutaml::Model::Liquid::IndexedAccess

        def [](key)
          "value_for_#{key}"
        end
      end

      instance = klass.new
      expect(instance.liquid_fetch("test")).to eq("value_for_test")
    end
  end
end
