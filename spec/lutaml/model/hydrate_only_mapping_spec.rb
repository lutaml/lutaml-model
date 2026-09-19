# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/lutaml/model"

module HydrateOnlyMapping
  class Message < Lutaml::Model::Serializable
    attribute :body, :string
    attribute :source_offset, :integer

    key_value do
      map "body", to: :body
      map "source_offset", to: :source_offset, serialize: false
    end
  end
end

RSpec.describe "hydrate-only mappings (serialize: false)" do
  let(:input) { { "body" => "hello", "source_offset" => 42 } }

  it "hydrates the attribute from input" do
    message = HydrateOnlyMapping::Message.from_hash(input)

    expect(message.body).to eq("hello")
    expect(message.source_offset).to eq(42)
  end

  it "omits the attribute from serialized output" do
    message = HydrateOnlyMapping::Message.from_hash(input)

    expect(message.to_hash).to eq("body" => "hello")
  end

  it "round-trips through JSON without the hidden key" do
    message = HydrateOnlyMapping::Message.from_json(input.to_json)

    expect(JSON.parse(message.to_json)).to eq("body" => "hello")
  end

  it "keeps the mapping through deep-copied mappings" do
    mapping = HydrateOnlyMapping::Message.mappings_for(:hash)
    rule = mapping.mappings.find { |r| r.to == :source_offset }

    expect(mapping.deep_dup.mappings.find { |r| r.to == :source_offset }
      .serialize?).to eq(rule.serialize?)
  end
end
