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
      expect(mapping.mapping_hash_values.size).to eq(2)
      expect(mapping.mapping_hash_values[0].name).to eq("type")
      expect(mapping.mapping_hash_values[0].delegate).to eq(:some_delegate)
      expect(mapping.mapping_hash_values[1].name).to eq("name")
      expect(mapping.mapping_hash_values[1].delegate).to be_nil
    end
  end

  describe "#deep_dup" do
    before do
      mapping.map(
        "type",
        to: :type,
        render_nil: true,
        delegate: :some_delegate,
        child_mappings: {
          id: :key,
          path: %i[path link],
          name: %i[path name],
        },
      )

      mapping.map(
        "name",
        with: {
          from: :model_from_json,
          to: :json_from_model,
        },
      )
    end

    let(:dup_mapping) { mapping.deep_dup }

    it "creates a deep duplicate" do
      expect(dup_mapping.object_id).not_to eq(mapping.object_id)
    end

    it "correctly duplicates mapping with `to:`" do
      m = mapping.mapping_hash_values[0]
      dup_m = dup_mapping.mapping_hash_values[0]

      expect(m.name).to eq(dup_m.name)
      expect(m.name.object_id).not_to eq(dup_m.name.object_id)

      # using symbols so object_id will remain same
      expect(m.to).to eq(dup_m.to)

      # render_nil is boolean so is constant with same object_id
      expect(m.render_nil).to eq(dup_m.render_nil)

      # using symbols so object_id will remain same
      expect(m.delegate).to eq(dup_m.delegate)

      expect(m.child_mappings).to eq(dup_m.child_mappings)
      expect(m.child_mappings.object_id).not_to eq(dup_m.child_mappings.object_id)
    end

    it "correctly duplicates mapping with custom methods" do
      m = mapping.mapping_hash_values[0]
      dup_m = dup_mapping.mapping_hash_values[0]

      expect(m.name).to eq(dup_m.name)
      expect(m.name.object_id).not_to eq(dup_m.name.object_id)

      # render_nil is boolean so is constant with same object_id
      expect(m.render_nil).to eq(dup_m.render_nil)

      expect(m.custom_methods).to eq(dup_m.custom_methods)
      expect(m.custom_methods.object_id).not_to eq(dup_m.custom_methods.object_id)
    end
  end

  context "with map_all option" do
    before do
      mapping.map_all(
        render_nil: true,
        delegate: :container,
      )
    end

    it "handles JSON, YAML, TOML mapping" do
      expect(mapping.mapping_hash_values[0].render_nil).to be true
      expect(mapping.mapping_hash_values[0].delegate).to eq(:container)
      expect(mapping.mapping_hash_values[0].raw_mapping?).to be true
    end
  end
end
