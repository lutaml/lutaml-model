# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

RSpec.describe "MappingRule get_transformers guard specs" do
  let(:rule_class) { Lutaml::Model::MappingRule }
  let(:attribute) { Lutaml::Model::Attribute.new("name", :string) }

  describe "rules with no transforms" do
    it "returns an empty array" do
      rule = rule_class.new("name", to: :name)
      result = rule.get_transformers(attribute)
      expect(result).to eq([])
    end

    it "returns a frozen result" do
      rule = rule_class.new("name", to: :name)
      result = rule.get_transformers(attribute)
      expect(result).to be_frozen
    end

    it "filters out non-Class transform values (empty hashes)" do
      rule = rule_class.new("name", to: :name)
      result = rule.get_transformers(attribute)
      # transform returns {} by default, but select! filters it out
      expect(result).to eq([])
    end
  end

  describe "get_transformers with transforms" do
    let(:transformer_class) do
      Class.new(Lutaml::Model::ValueTransformer) do
        def self.from(value, _format)
          value
        end

        def self.to(value, _format)
          value
        end

        def self.can_transform?(_direction, _format)
          true
        end

        def self.name
          "TestTransformer"
        end
      end
    end

    it "returns transformer class when rule has a Class transform" do
      rule = rule_class.new("name", to: :name, transform: transformer_class)
      result = rule.get_transformers(attribute)
      expect(result).to include(transformer_class)
    end

    it "returns frozen array when transformers are present" do
      rule = rule_class.new("name", to: :name, transform: transformer_class)
      result = rule.get_transformers(attribute)
      expect(result).to be_frozen
    end

    it "filters out non-Class transformers" do
      rule = rule_class.new("name", to: :name,
                                    transform: { from: ->(v) { v } })
      result = rule.get_transformers(attribute)
      expect(result).to eq([])
    end
  end
end
