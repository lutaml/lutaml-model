# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/lutaml/model"
require "lutaml/xml/adapter/nokogiri_adapter"

# Runtimes without a source compiler (Opal) define the attribute
# accessors and the state-defaults seed from blocks instead of a String
# class_eval. These specs force that block form on MRI and check it
# behaves exactly like the compiled form.
module AttributeDefinitionBlockFormSpec
  module_function

  def define_model(klass)
    klass.class_eval do
      attribute :name, :string
      attribute :count, :integer
      attribute :tags, :string, collection: true
      # "char" is an enum shorthand, so the second :char definition
      # redefines the setter but keeps the first Attribute's accessor.
      attribute :align, :string, values: %w[char left]
      attribute :char, :integer
      attribute :char, :string
      # String names, mutated once defined: the accessors must keep
      # reading the ivar named at definition time.
      label = +"label"
      notes = +"notes"
      attribute label, :integer
      attribute notes, :string, collection: true
      label << "x"
      notes << "x"

      xml do
        element "item"
        ordered
        map_attribute "name", to: :name
        map_element "count", to: :count
        map_element "tag", to: :tags
        map_element "char", to: :char
      end

      key_value do
        map "name", to: :name
        map "count", to: :count
        map "tags", to: :tags
        map "char", to: :char
      end
    end
    klass
  end

  def build_model
    define_model(Class.new(Lutaml::Model::Serializable))
  end

  def element_order(model)
    model.element_order.map { |e| [e.type, e.name, e.text_content] }
  end

  def arity_error(model, name)
    model.public_send(name, "1", "2")
    nil
  rescue ArgumentError => e
    e.message
  end

  def observe(klass)
    fresh = klass.new
    set = klass.new
    set.name = "a"
    set.count = "5"
    set.tags("x")
    set.tags("y")
    set.char = "7"
    # A parsed instance with no tags still holds the lazy sentinel.
    emptied = klass.from_xml('<item name="z"/>')
    sentinel_before_nil = emptied.instance_variable_get(:@tags)
      .equal?(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION)
    emptied.tags = nil
    xml = set.to_xml
    parsed = klass.from_xml(xml)

    seed = klass.send(:compiled_state_defaults_name!, :default)
    seeded = klass.new.send(seed)

    {
      seed_return: [seeded.class, seeded.equal?(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION)],
      fresh_scalar_uninitialized: Lutaml::Model::Utils.uninitialized?(
        fresh.instance_variable_get(:@name),
      ),
      fresh_collection_sentinel: fresh.instance_variable_get(:@tags)
        .equal?(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION),
      fresh_readers: [fresh.name, fresh.count, fresh.tags],
      set_readers: [set.name, set.count, set.tags, set.char],
      set_using_default: %i[name count tags].map { |a| set.using_default?(a) },
      sentinel_before_nil: sentinel_before_nil,
      nil_keeps_sentinel: emptied.instance_variable_get(:@tags)
        .equal?(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION),
      getter_with_arg: klass.new.tap { |m| m.count("3") }.count,
      assign_parsed_skips_cast: klass.new.tap { |m| m.__assign_parsed_count = "3" }.count,
      built_order: element_order(klass.new do |m|
        m.count = "1"
        m.tags = %w[p q]
        m.tags("r")
      end),
      string_names: klass.new.tap do |m|
        m.label = "4"
        m.notes("n")
      end.then { |m| [m.label, m.notes, m.instance_variables.grep(/label|notes/).sort] },
      two_args: %i[count tags label notes].map { |a| arity_error(klass.new, a) },
      xml: xml,
      json: set.to_json,
      parsed: [parsed.name, parsed.count, parsed.tags, parsed.char],
      parsed_equal: parsed == set,
    }
  end
end

RSpec.describe Lutaml::Model::Serialize::AttributeDefinition do
  let(:compiled) { AttributeDefinitionBlockFormSpec.observe(AttributeDefinitionBlockFormSpec.build_model) }

  it "compiles accessors from source by default on MRI" do
    expect(described_class.source_compilation?).to be(true)
  end

  it "defines the block form without String class_eval and matches the compiled form" do
    expected = compiled
    allow(described_class).to receive(:source_compilation?).and_return(false)
    klass = Class.new(Lutaml::Model::Serializable)
    allow(klass).to receive(:class_eval).and_wrap_original do |original, *args, &block|
      raise "String class_eval used: #{args.first}" if args.first.is_a?(String)

      original.call(*args, &block)
    end
    AttributeDefinitionBlockFormSpec.define_model(klass)

    expect(AttributeDefinitionBlockFormSpec.observe(klass)).to eq(expected)
  end
end
