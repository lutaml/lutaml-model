# frozen_string_literal: true

require "spec_helper"

# lutaml-model#1122: the per-register flattened-mapping memo (round 7)
# froze the rule list before a second DSL block (a mixin-installed
# key_value combined with an in-class one) added its rules — the
# InternetDraft "version" rule vanished from to_hash. Every DSL and
# import mutation point now invalidates the memo.
module KvFlattenMemoSpec
  module Serialization
    def self.included(base)
      base.key_value do
        map "_type", to: :type
        map "number", to: :number
      end
    end
  end

  class Draft < Lutaml::Model::Serializable
    include Serialization

    attribute :type, :string
    attribute :number, :string
    attribute :version, :string

    key_value do
      map "version", to: :version
    end
  end
end

RSpec.describe "KV flatten memo vs late DSL blocks (#1122)" do
  it "keeps rules added by a later key_value block" do
    model = KvFlattenMemoSpec::Draft.new(
      type: "internet_draft", number: "draft-ietf-quic-transport",
      version: "34"
    )
    h = model.to_hash
    expect(h["version"]).to eq("34")
    expect(h["number"]).to eq("draft-ietf-quic-transport")
  end

  it "keeps the memo effective for stable rule sets" do
    model = KvFlattenMemoSpec::Draft.new(number: "x", version: "1")
    first = model.to_hash
    expect(model.to_hash).to eq(first)
  end
end
