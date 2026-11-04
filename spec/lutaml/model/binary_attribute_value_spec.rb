# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Binary String attribute values" do
  let(:bytes_type) do
    Class.new(Lutaml::Model::Type::Value) do
      def self.cast(value, *)
        value.is_a?(String) ? value.b : value
      end
    end
  end

  let(:model_class) do
    type = bytes_type
    Class.new(Lutaml::Model::Serializable) do
      attribute :data, type
      attribute :text, :string
    end
  end

  let(:raw) { "\xFF\x00\xC3\x28\x89".b }

  it "keeps every byte a non-text type returns" do
    expect(model_class.new(data: raw).data.bytes).to eq(raw.bytes)
  end

  it "still transcodes a binary String given to a :string attribute" do
    text = model_class.new(text: "plain".b).text
    expect([text, text.encoding]).to eq(["plain", Encoding::UTF_8])
  end
end
