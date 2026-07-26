# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/lutaml/model"
require "lutaml/xml/adapter/nokogiri_adapter"

# Specs for Lutaml::Model::Serialize::Builder — the module that gives
# Serializable the `Klass.new do |x| ... end` block syntax.
#
# These specs exist because of a regression where direct setters
# (`x.attr = v`) inside the builder block silently dropped attributes
# from serialized output while appender calls (`x.attr(v)`) worked.
# The root cause was that only getter-with-arg paths called track_order;
# generated setters did not. The fix centralises mutation recording via
# Builder#record_mutation / record_mutation_collection, and the
# serializer's apply_remaining_rules acts as a safety net so element
# values are never silently dropped.
#
# These specs cover the invariant ("no silent data loss"), call-order
# preservation, round-trip parity, equivalence between .tap and block,
# the no-op guarantee for non-ordered models, and the wholesale
# collection assignment case.
RSpec.describe "Lutaml::Model::Serialize::Builder" do
  let(:ordered_klass) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :singular, :string
      attribute :items, :string, collection: true

      xml do
        element "container"
        ordered
        map_element "singular", to: :singular
        map_element "items", to: :items
      end
    end
  end

  let(:mixed_klass) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :singular, :string
      attribute :items, :string, collection: true

      xml do
        element "container"
        mixed_content
        map_element "singular", to: :singular
        map_element "items", to: :items
      end
    end
  end

  let(:plain_klass) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :singular, :string
      attribute :items, :string, collection: true

      xml do
        element "container"
        map_element "singular", to: :singular
        map_element "items", to: :items
      end
    end
  end

  shared_examples "no silent data loss across mutation styles" do
    it "appender-only: emits every call in order" do
      obj = ordered_klass.new do |x|
        x.singular "first"
        x.items "a"
        x.items "b"
      end

      xml = obj.to_xml
      expect(xml).to be_xml_equivalent_to(<<~XML)
        <container>
          <singular>first</singular>
          <items>a</items>
          <items>b</items>
        </container>
      XML
      expect(obj.element_order.map(&:name)).to eq(%w[singular items items])
    end

    it "direct setter for singular: still emits the element" do
      obj = ordered_klass.new do |x|
        x.singular = "first"
        x.items "a"
      end

      xml = obj.to_xml
      expect(xml).to be_xml_equivalent_to(<<~XML)
        <container>
          <singular>first</singular>
          <items>a</items>
        </container>
      XML
      expect(obj.element_order.map(&:name)).to eq(%w[singular items])
    end

    it "wholesale collection assignment: emits one element per item" do
      obj = ordered_klass.new do |x|
        x.singular "first"
        x.items = %w[a b c]
      end

      xml = obj.to_xml
      expect(xml).to be_xml_equivalent_to(<<~XML)
        <container>
          <singular>first</singular>
          <items>a</items>
          <items>b</items>
          <items>c</items>
        </container>
      XML
      expect(obj.element_order.map(&:name)).to eq(%w[singular items items items])
    end

    it "all direct setters: emits in call order" do
      obj = ordered_klass.new do |x|
        x.singular = "first"
        x.items = %w[a b]
      end

      xml = obj.to_xml
      expect(xml).to be_xml_equivalent_to(<<~XML)
        <container>
          <singular>first</singular>
          <items>a</items>
          <items>b</items>
        </container>
      XML
    end

    it "mixed style preserves call order across setters and appenders" do
      obj = ordered_klass.new do |x|
        x.items "a"
        x.singular = "middle"
        x.items "b"
      end

      xml = obj.to_xml
      expect(xml).to be_xml_equivalent_to(<<~XML)
        <container>
          <items>a</items>
          <singular>middle</singular>
          <items>b</items>
        </container>
      XML
    end
  end

  describe "no silent data loss" do
    it_behaves_like "no silent data loss across mutation styles"

    it "mixed_content model emits setter-only attributes too" do
      obj = mixed_klass.new do |x|
        x.singular = "first"
        x.items "a"
      end

      xml = obj.to_xml
      expect(xml).to include("<singular>first</singular>")
      expect(xml).to include("<items>a</items>")
      expect(obj.element_order.map(&:name)).to eq(%w[singular items])
    end
  end

  describe "call order preservation" do
    it "reverse declaration order is honoured via direct setters" do
      obj = ordered_klass.new do |x|
        x.items = %w[a b]
        x.singular = "last"
      end

      xml = obj.to_xml
      items_pos = xml.index("<items>")
      singular_pos = xml.index("<singular>")
      expect(items_pos).to be < singular_pos
      expect(obj.element_order.map(&:name)).to eq(%w[items items singular])
    end

    it "reverse declaration order is honoured via appenders" do
      obj = ordered_klass.new do |x|
        x.items "a"
        x.singular "last"
      end

      xml = obj.to_xml
      items_pos = xml.index("<items>")
      singular_pos = xml.index("<singular>")
      expect(items_pos).to be < singular_pos
      expect(obj.element_order.map(&:name)).to eq(%w[items singular])
    end
  end

  describe "round-trip parity" do
    it "ordered: parses and re-emits equivalent XML" do
      original = <<~XML
        <container>
          <items>a</items>
          <singular>middle</singular>
          <items>b</items>
        </container>
      XML

      parsed = ordered_klass.from_xml(original)
      expect(parsed.to_xml).to be_xml_equivalent_to(original)
    end

    it "mixed_content: parses and re-emits equivalent XML" do
      original = <<~XML
        <container>before <items>a</items> mid <singular>x</singular> end</container>
      XML

      parsed = mixed_klass.from_xml(original)
      roundtrip = parsed.to_xml
      expect(roundtrip).to include("<items>a</items>")
      expect(roundtrip).to include("<singular>x</singular>")
    end
  end

  describe ".tap vs builder block equivalence" do
    it "produces identical element_order presence and XML shape" do
      via_tap = ordered_klass.new.tap do |x|
        x.singular = "first"
        x.items = %w[a b]
      end

      via_block = ordered_klass.new do |x|
        x.singular = "first"
        x.items = %w[a b]
      end

      # .tap path does not enable tracking; both must still emit the same XML.
      expect(via_tap.element_order).to be_nil
      expect(via_block.element_order).not_to be_nil
      expect(via_tap.to_xml).to be_xml_equivalent_to(via_block.to_xml)
    end
  end

  describe "no-op guarantee when not tracking" do
    it "plain (non-ordered) models do not allocate element_order entries" do
      obj = plain_klass.new do |x|
        x.singular = "first"
        x.items "a"
      end

      expect(obj.element_order).to be_nil
      expect { obj.to_xml }.not_to raise_error
    end

    it "ordered models constructed without a block do not track" do
      obj = ordered_klass.new
      obj.singular = "first"
      obj.items = %w[a b]

      expect(obj.element_order).to be_nil
      expect(obj.to_xml).to include("<singular>first</singular>")
    end
  end

  describe "wholesale collection reassignment" do
    it "tracks one entry per item across multiple assignments" do
      obj = ordered_klass.new do |x|
        x.items = %w[a b]
        x.items = %w[c d e]
      end

      # element_order is a log of mutations, not a reflection of final state,
      # so both assignments are recorded. The serializer emits the current
      # value of the attribute via element_order in recorded order; the
      # safety net guarantees no data loss.
      expect(obj.element_order.map(&:name)).to eq(%w[items items items items items])
      xml = obj.to_xml
      # The serialized output must contain all current items
      expect(xml).to include("<items>c</items>")
      expect(xml).to include("<items>d</items>")
      expect(xml).to include("<items>e</items>")
    end
  end

  describe "no-silent-drop invariant (cross-cutting)" do
    # The bug class: any attribute with a non-default value MUST appear in
    # the serialized output, regardless of how it was set. This spec is the
    # regression guard for the whole class of bug, not just one instance.
    shared_examples "no silent drop" do |description, mutation_block|
      it "does not silently drop any attribute set via: #{description}" do
        obj = ordered_klass.new(&mutation_block)
        xml = obj.to_xml

        if !obj.singular.nil? && !obj.singular.to_s.empty?
          expect(xml).to include("<singular>"), "singular was dropped from output"
        end
        return if obj.items.nil? || obj.items.empty?

        obj.items.each do |item|
          expect(xml).to include("<items>#{item}</items>"),
                         "items element for #{item.inspect} was dropped from output"
        end
      end
    end

    it_behaves_like "no silent drop",
                    "singular setter + wholesale items setter",
                    lambda { |x|
                      x.singular = "v"
                      x.items = %w[a b]
                    }
    it_behaves_like "no silent drop",
                    "all appenders",
                    lambda { |x|
                      x.singular "v"
                      x.items "a"
                      x.items "b"
                    }
    it_behaves_like "no silent drop",
                    "singular setter + items appender (the original bug)",
                    lambda { |x|
                      x.singular = "v"
                      x.items "a"
                      x.items "b"
                    }
    it_behaves_like "no silent drop",
                    "singular appender + wholesale items setter",
                    lambda { |x|
                      x.singular "v"
                      x.items = %w[a b]
                    }
  end
end
