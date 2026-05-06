# frozen_string_literal: true

require "spec_helper"
require "liquid"
require "tmpdir"
require "fileutils"

# These specs verify the Liquid API surface that Lutaml::Model::Liquefiable
# depends on. They are behavior-based, not version-gated — if these pass,
# the installed Liquid version provides everything we need.
#
# Liquid features exercised here:
#   - Liquid::Drop (base class for generated drop objects)
#   - Liquid::Template.parse / #render (template compilation and execution)
#   - Liquid::LocalFileSystem (partial resolution for {% include %})
#   - to_liquid protocol (automatic drop conversion in render contexts)
#   - Template tags: {{ var }}, {% for %}, {% if %}, {% assign %}
RSpec.describe "Liquid compatibility for Lutaml::Model::Liquefiable" do
  # ── Core API availability ──────────────────────────────────────────────

  describe "required Liquid classes and methods" do
    it "provides Liquid::Drop as a base class" do
      expect(defined?(Liquid::Drop)).to eq("constant")
      drop = Class.new(Liquid::Drop).new
      expect(drop).to be_a(Liquid::Drop)
    end

    it "provides Liquid::Template.parse" do
      expect(Liquid::Template).to respond_to(:parse)
    end

    it "provides template#render with a hash of variables" do
      template = Liquid::Template.parse("{{ msg }}")
      expect(template.render("msg" => "hello")).to eq("hello")
    end

    it "provides Liquid::LocalFileSystem" do
      expect(defined?(Liquid::LocalFileSystem)).to eq("constant")
    end

    it "supports the to_liquid protocol on strings and integers" do
      expect("hello".to_liquid).to eq("hello")
      expect(42.to_liquid).to eq(42)
    end
  end

  # ── Drop generation from Serializable models ───────────────────────────

  describe "drop generation for Serializable models" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "Widget"
        end

        attribute :label, :string
        attribute :count, :integer
      end
    end

    let(:instance) { model_class.new(label: "Sprocket", count: 3) }

    it "generates a Drop subclass inheriting from Liquid::Drop" do
      drop = instance.to_liquid
      expect(drop).to be_a(Liquid::Drop)
    end

    it "exposes attributes as drop methods" do
      drop = instance.to_liquid
      expect(drop.label).to eq("Sprocket")
      expect(drop.count).to eq(3)
    end

    it "returns the same Drop class for all instances" do
      drop_class = instance.to_liquid.class
      other = model_class.new(label: "Gear", count: 1)
      expect(other.to_liquid.class).to eq(drop_class)
    end

    it "does not re-register methods on subsequent calls" do
      instance.to_liquid
      expect do
        instance.to_liquid
      end.not_to(change do
        instance.to_liquid.class.instance_methods(false).sort
      end)
    end
  end

  # ── Nested model drops ─────────────────────────────────────────────────

  describe "nested model composition" do
    let(:inner_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "Detail"
        end

        attribute :color, :string
      end
    end

    let(:outer_class) do
      inner = inner_class

      Class.new(Lutaml::Model::Serializable) do
        define_method(:inner_class) { inner }

        def self.name
          "Container"
        end

        attribute :title, :string
        attribute :detail, inner
      end
    end

    let(:instance) do
      outer_class.new(title: "Box", detail: inner_class.new(color: "blue"))
    end

    it "converts nested models to drops via to_liquid" do
      drop = instance.to_liquid
      expect(drop.detail).to be_a(Liquid::Drop)
      expect(drop.detail.color).to eq("blue")
    end

    it "resolves nested access in templates" do
      template = Liquid::Template.parse("{{ instance.detail.color }}")
      result = template.render("instance" => instance)
      expect(result).to eq("blue")
    end
  end

  # ── Collections ────────────────────────────────────────────────────────

  describe "collection handling" do
    let(:item_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "Item"
        end

        attribute :name, :string
      end
    end

    let(:container_class) do
      item_klass = item_class

      Class.new(Lutaml::Model::Serializable) do
        define_method(:item_class) { item_klass }

        def self.name
          "ItemContainer"
        end

        attribute :items, item_klass, collection: true
      end
    end

    let(:instance) do
      container_class.new(
        items: [
          item_class.new(name: "Alpha"),
          item_class.new(name: "Beta"),
        ],
      )
    end

    it "converts array of models to array of drops" do
      drops = instance.to_liquid.items
      expect(drops).to all(be_a(Liquid::Drop))
      expect(drops.map(&:name)).to eq(["Alpha", "Beta"])
    end

    it "iterates collections in {% for %} loops" do
      template = Liquid::Template.parse(<<~LIQUID)
        {% for item in container.items %}{{ item.name }},{% endfor %}
      LIQUID
      result = template.render("container" => instance)
      expect(result.strip).to eq("Alpha,Beta,")
    end
  end

  # ── Custom liquid mappings ─────────────────────────────────────────────

  describe "custom liquid mappings via liquid block" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "MappedWidget"
        end

        attribute :path, :string
        attribute :source, :string

        liquid do
          map "full_path", to: :computed_path
          map "summary", to: :formatted_summary
        end

        def computed_path
          "/app/#{path}"
        end

        def formatted_summary
          "#{source} (#{path})"
        end
      end
    end

    let(:instance) { model_class.new(path: "index.xml", source: "Hello") }

    it "maps custom keys to instance methods" do
      drop = instance.to_liquid
      expect(drop.full_path).to eq("/app/index.xml")
      expect(drop.summary).to eq("Hello (index.xml)")
    end

    it "renders custom mappings in templates" do
      template = Liquid::Template.parse("{{ w.full_path }} | {{ w.summary }}")
      result = template.render("w" => instance)
      expect(result).to eq("/app/index.xml | Hello (index.xml)")
    end

    it "still exposes original attributes alongside custom mappings" do
      drop = instance.to_liquid
      expect(drop.path).to eq("index.xml")
      expect(drop.source).to eq("Hello")
    end
  end

  # ── Conditional and control-flow templates ─────────────────────────────

  describe "template control flow with drops" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "ConditionalModel"
        end

        attribute :title, :string
        attribute :score, :integer
      end
    end

    it "handles {% if %} with drop attributes" do
      instance = model_class.new(title: "present", score: 10)
      template = Liquid::Template.parse(<<~LIQUID)
        {% if m.title %}HAS_TITLE{% else %}NO_TITLE{% endif %}
      LIQUID
      expect(template.render("m" => instance).strip).to eq("HAS_TITLE")

      empty = model_class.new(title: nil, score: 0)
      expect(template.render("m" => empty).strip).to eq("NO_TITLE")
    end

    it "handles {% assign %} and expressions with drop values" do
      instance = model_class.new(title: "demo", score: 42)
      template = Liquid::Template.parse(<<~LIQUID)
        {% assign threshold = 10 %}{% if m.score > threshold %}HIGH{% else %}LOW{% endif %}
      LIQUID
      expect(template.render("m" => instance).strip).to eq("HIGH")
    end
  end

  # ── Inheritance ────────────────────────────────────────────────────────

  describe "drop inheritance across class hierarchy" do
    let(:parent_class) do
      Class.new(Lutaml::Model::Serializable) do
        def self.name
          "Parent"
        end

        attribute :name, :string
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        def self.name
          "Child"
        end

        attribute :age, :integer
      end
    end

    it "inherits attribute drops from the parent" do
      child = child_class.new(name: "Alice", age: 5)
      drop = child.to_liquid
      expect(drop.name).to eq("Alice")
      expect(drop.age).to eq(5)
    end

    it "parent and child have distinct drop classes" do
      parent = parent_class.new(name: "Bob")
      child = child_class.new(name: "Alice", age: 5)
      expect(parent.to_liquid.class).not_to eq(child.to_liquid.class)
    end
  end

  # ── Non-Serializable Liquefiable ───────────────────────────────────────

  describe "Liquefiable without Serializable" do
    let(:plain_class) do
      Class.new do
        include Lutaml::Model::Liquefiable

        def self.name
          "PlainObject"
        end

        def initialize(label)
          @label = label
        end

        def label
          @label
        end

        liquid do
          map "label", to: :label
        end
      end
    end

    it "creates a drop class inheriting from Liquid::Drop" do
      instance = plain_class.new("test")
      expect(instance.to_liquid).to be_a(Liquid::Drop)
    end

    it "exposes mapped methods on the drop" do
      instance = plain_class.new("hello")
      expect(instance.to_liquid.label).to eq("hello")
    end

    it "renders in templates" do
      instance = plain_class.new("world")
      template = Liquid::Template.parse("{{ obj.label }}")
      expect(template.render("obj" => instance)).to eq("world")
    end
  end

  # ── Error handling ─────────────────────────────────────────────────────

  describe "error handling" do
    it "raises LiquidNotEnabledError when Liquid is not loaded" do
      allow(Object).to receive(:const_defined?).with(:Liquid).and_return(false)
      klass = Class.new do
        include Lutaml::Model::Liquefiable
      end
      instance = klass.new
      expect { instance.to_liquid }.to raise_error(
        Lutaml::Model::LiquidNotEnabledError,
      )
    end

    it "raises LiquidDropAlreadyRegisteredError on duplicate registration" do
      allow(Object).to receive(:const_defined?).with(:Liquid).and_call_original
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name
          "DupTestModel"
        end

        attribute :x, :string
      end
      # Drop already registered during class definition
      expect do
        klass.register_liquid_drop_class
      end.to raise_error(Lutaml::Model::LiquidDropAlreadyRegisteredError)
    end

    it "raises LiquidClassNotFoundError for missing custom drop class" do
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name
          "MissingDropModel"
        end

        attribute :x, :string

        liquid_class "NonexistentDrop"
      end
      instance = klass.new(x: "test")
      expect { instance.to_liquid }.to raise_error(
        Lutaml::Model::LiquidClassNotFoundError,
        /NonexistentDrop/,
      )
    end

    it "raises NoAttributesDefinedLiquidError for attribute-less Serializable" do
      klass = Class.new(Lutaml::Model::Serializable) do
        def self.name
          "NoAttrsModel"
        end
      end
      instance = klass.new
      expect { instance.to_liquid }.to raise_error(
        Lutaml::Model::NoAttributesDefinedLiquidError,
        /NoAttrsModel/,
      )
    end
  end

  # ── LocalFileSystem (partials via {% include %}) ───────────────────────

  describe "partial rendering with Liquid::LocalFileSystem" do
    let(:template_dir) do
      Dir.mktmpdir
    end

    after do
      FileUtils.remove_entry(template_dir)
    end

    it "resolves {% include %} partials via LocalFileSystem" do
      File.write(File.join(template_dir, "_item.liquid"), <<~LIQUID)
        [{{ item.name }}]
      LIQUID

      item_class = Class.new(Lutaml::Model::Serializable) do
        def self.name
          "FsItem"
        end

        attribute :name, :string
      end

      item = item_class.new(name: "Alpha")
      template = Liquid::Template.new
      template.registers[:file_system] = Liquid::LocalFileSystem.new(template_dir)
      template.parse(<<~LIQUID)
        {% include 'item' item: item %}
      LIQUID

      result = template.render("item" => item)
      expect(result.strip).to eq("[Alpha]")
    end
  end
end
