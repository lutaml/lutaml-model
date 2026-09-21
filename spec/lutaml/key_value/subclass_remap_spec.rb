# frozen_string_literal: true

require "spec_helper"

# A subclass that remaps a parent wire key onto a different attribute
# must replace the parent's rule, not accumulate beside it. Pre-#88
# (hash-keyed by wire name) this was automatic; the #88 array form
# only replaced on matching `to:`, leaving both rules active and
# breaking consumers like glossarist's V2::Citation (base maps
# `ref → Ref`, V2 remaps `ref → text`).
RSpec.describe "Key-value subclass wire-key remap" do
  it "replaces the parent rule when the subclass remaps the same key to a different attribute" do
    base = Class.new(Lutaml::Model::Serializable) do
      attribute :ref, :string
      attribute :label, :string

      key_value do
        map :ref, to: :ref
      end
    end

    child = Class.new(base) do
      key_value do
        map :ref, to: :label
      end
    end

    ref_spellings = [:ref, "ref"].freeze
    rules = child.mappings_for(:yaml).mappings.select do |r|
      ref_spellings.include?(r.name)
    end
    # Only the child's rule must remain
    expect(rules.map(&:to)).to eq([:label])
  end

  it "still accumulates when_attribute partitions of the same wire key" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :a, :string
      attribute :b, :string

      key_value do
        map :body, to: :a, when_attribute: { "type" => "a" }
        map :body, to: :b, when_attribute: { "type" => "b" }
      end
    end

    body_spellings = [:body, "body"].freeze
    rules = klass.mappings_for(:yaml).mappings.select do |r|
      body_spellings.include?(r.name)
    end
    expect(rules.map(&:to)).to match_array(expected_targets)
  end
end
