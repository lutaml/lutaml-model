# spec/lutaml/model/key_value_mapping_spec.rb
require "spec_helper"
require_relative "../../../lib/lutaml/model/key_value_mapping"
require_relative "../../../lib/lutaml/model/key_value_mapping_rule"

RSpec.describe Lutaml::Model::KeyValueMapping do
  let(:mapping) { described_class.new }

  context "with delegate option" do
    before do
      mapping.map("type", to: :type, delegate: :some_delegate)
      mapping.map("name", to: :name)
    end

    it "adds mappings with delegate option" do
      expect(mapping.mappings.size).to eq(2)
      expect(mapping.mappings[0].name).to eq("type")
      expect(mapping.mappings[0].delegate).to eq(:some_delegate)
      expect(mapping.mappings[1].name).to eq("name")
      expect(mapping.mappings[1].delegate).to be_nil
    end
  end
end
