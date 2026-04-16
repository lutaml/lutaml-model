# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lutaml::Model::Choice, "#restrict and #remove_attribute" do
  before do
    stub_const("ChoiceRestrictParent", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :email, :string
    end)
  end

  describe "#restrict" do
    it "restricts a predefined attribute inside a choice block" do
      stub_const("ChoiceRestrictModel", Class.new(Lutaml::Model::Serializable) do
        attribute :foo, :string, collection: 1..10

        choice min: 1, max: 1 do
          restrict :foo, collection: 2..5
        end
      end)

      attr = ChoiceRestrictModel.attributes[:foo]
      expect(attr.options[:collection]).to eq(2..5)
      choice = ChoiceRestrictModel.choice_attributes.first
      expect(choice.attributes).to include(attr)
    end

    it "raises UndefinedAttributeError for non-existent attribute" do
      expect {
        stub_const("ChoiceRestrictBadModel", Class.new(Lutaml::Model::Serializable) do
          choice min: 1, max: 1 do
            restrict :nonexistent, collection: 1..2
          end
        end)
      }.to raise_error(Lutaml::Model::UndefinedAttributeError)
    end

    it "restricts an imported model attribute inside a choice block" do
      stub_const("ChoiceImportModel", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :age, :integer

        choice min: 1, max: 1 do
          import_model_attributes ChoiceRestrictParent
          restrict :age, values: [18, 21, 30]
        end
      end)

      attr = ChoiceImportModel.attributes[:age]
      expect(attr.options[:values]).to eq([18, 21, 30])
    end

    it "marks the attribute as belonging to the choice" do
      stub_const("ChoiceRestrictOwnedModel", Class.new(Lutaml::Model::Serializable) do
        attribute :tag, :string

        choice min: 0, max: 1 do
          restrict :tag, values: %w[a b c]
        end
      end)

      attr = ChoiceRestrictOwnedModel.attributes[:tag]
      expect(attr.options[:choice]).to be_a(Lutaml::Model::Choice)
    end

    it "does not duplicate the attribute if restrict is called twice" do
      stub_const("ChoiceRestrictDupModel", Class.new(Lutaml::Model::Serializable) do
        attribute :val, :integer

        choice min: 0, max: 1 do
          restrict :val, values: [1, 2]
          restrict :val, values: [1, 2, 3]
        end
      end)

      choice = ChoiceRestrictDupModel.choice_attributes.first
      count = choice.attributes.count { |a| !a.is_a?(Lutaml::Model::Choice) && a.name == :val }
      expect(count).to eq(1)
      expect(ChoiceRestrictDupModel.attributes[:val].options[:values]).to eq([1, 2, 3])
    end
  end

  describe "#remove_attribute" do
    it "removes an attribute from the choice block" do
      stub_const("ChoiceRemoveModel", Class.new(Lutaml::Model::Serializable) do
        attribute :keep, :string
        attribute :drop, :string

        choice min: 0, max: 1 do
          attribute :keep, :string
          attribute :drop, :string
          remove_attribute :drop
        end
      end)

      choice = ChoiceRemoveModel.choice_attributes.first
      attr_names = choice.attributes.map { |a| a.is_a?(Lutaml::Model::Choice) ? nil : a.name }.compact
      expect(attr_names).to eq([:keep])
    end

    it "clears the choice option from the removed attribute" do
      stub_const("ChoiceRemoveOptModel", Class.new(Lutaml::Model::Serializable) do
        attribute :item, :string

        choice min: 0, max: 1 do
          attribute :item, :string
          remove_attribute :item
        end
      end)

      choice = ChoiceRemoveModel rescue nil
      attr = ChoiceRemoveOptModel.attributes[:item]
      # The top-level :item attribute should still exist without :choice
      # since the one in the choice was a different instance
      expect(attr.options[:choice]).to be_nil
    end

    it "returns false if the attribute is not in the choice" do
      result = nil
      stub_const("ChoiceRemoveNotFoundModel", Class.new(Lutaml::Model::Serializable) do
        attribute :x, :string

        choice min: 0, max: 1 do
          result = remove_attribute(:nonexistent)
        end
      end)

      expect(result).to eq(false)
    end

    it "invalidates the flat_attributes cache" do
      stub_const("ChoiceRemoveCacheModel", Class.new(Lutaml::Model::Serializable) do
        attribute :a, :string
        attribute :b, :string

        choice min: 0, max: 1 do
          attribute :a, :string
          attribute :b, :string
        end
      end)

      choice = ChoiceRemoveCacheModel.choice_attributes.first
      expect(choice.flat_attributes.map(&:name)).to contain_exactly(:a, :b)
      choice.remove_attribute(:b)
      expect(choice.flat_attributes.map(&:name)).to contain_exactly(:a)
    end
  end
end
