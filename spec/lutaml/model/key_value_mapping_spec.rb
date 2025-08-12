require "spec_helper"

RSpec.describe Lutaml::Model::KeyValueMapping do
  let(:mapping) { described_class.new(:json) }

  describe "find_by_to! error handling" do
    it "raises NoMappingFoundError when mapping is missing in key_value mapping" do
      expect do
        mapping.find_by_to!("nonexistent")
      end.to raise_error(Lutaml::Model::NoMappingFoundError, /No mapping available for `nonexistent`/)
    end
  end

  it "raises error when :to is nil and :with single mapping" do
    expect do
      mapping.map("test", with: { from: :from_method })
    end.to raise_error(
      Lutaml::Model::IncorrectMappingArgumentsError,
      ":with argument for mapping 'test' requires :to and :from keys",
    )
  end

  it "raises error when :to is nil and :with arguments have nil values" do
    expect do
      mapping.map("test", with: { from: nil, to: nil })
    end.to raise_error(
      Lutaml::Model::IncorrectMappingArgumentsError,
      ":with argument for mapping 'test' requires :to and :from keys",
    )
  end

  it "does not raise error when using :to, and :with has single mapping" do
    expect do
      mapping.map("test", to: :field, with: { to: :to_method })
    end.not_to raise_error
  end

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

    it "correctly duplicates mapping with format" do
      expect(mapping.format).to eq(dup_mapping.format)
    end

    it "correctly duplicates mapping with `to:`" do
      m = mapping.mappings[0]
      dup_m = dup_mapping.mappings[0]

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

      expect(m.format).to eq(dup_m.format)
    end

    it "correctly duplicates mapping with custom methods" do
      m = mapping.mappings[0]
      dup_m = dup_mapping.mappings[0]

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
      expect(mapping.mappings[0].render_nil).to be true
      expect(mapping.mappings[0].delegate).to eq(:container)
      expect(mapping.mappings[0].raw_mapping?).to be true
    end
  end

  describe "validation errors" do
    it "raises error when render_nil is :as_blank" do
      mapping = described_class.new
      expect do
        mapping.map("test", to: :field, render_nil: :as_blank)
      end.to raise_error(
        Lutaml::Model::IncorrectMappingArgumentsError,
        ":as_blank is not supported for key-value mappings",
      )
    end

    context "with TOML format" do
      let(:mapping) { Lutaml::Model::Toml::Mapping.new }

      it "raises error when render_nil is :as_nil" do
        expect do
          mapping.map("test", to: :field, render_nil: :as_nil)
        end.to raise_error(
          Lutaml::Model::IncorrectMappingArgumentsError,
          "nil values are not supported in toml format",
        )
      end

      it "raises error when render_empty is :as_nil" do
        expect do
          mapping.map("test", to: :field, render_empty: :as_nil)
        end.to raise_error(
          Lutaml::Model::IncorrectMappingArgumentsError,
          "nil values are not supported in toml format",
        )
      end
    end
  end
end
