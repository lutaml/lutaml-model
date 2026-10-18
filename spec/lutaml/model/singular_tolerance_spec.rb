# frozen_string_literal: true

require "spec_helper"

# #971: a singular attribute may ask ingest to keep the leading value
# when the mapper collects more than one element (relaton's upstream
# bibitems carry multiple <formattedref> elements). Default stays
# strict: the over-count remains a CollectionTrueMissingError.
RSpec.describe "singular_tolerance attribute option" do
  let(:item_class) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string
    end
  end

  before do
    stub_const("ToleranceItem", item_class)
  end

  describe "option validation" do
    it "accepts :first" do
      expect do
        Lutaml::Model::Attribute.new(:ref, "ToleranceItem",
                                     singular_tolerance: :first)
      end.not_to raise_error
    end

    it "accepts omission (strict default)" do
      expect do
        Lutaml::Model::Attribute.new(:ref, "ToleranceItem")
      end.not_to raise_error
    end

    it "rejects unsupported tolerances" do
      expect do
        Lutaml::Model::Attribute.new(:ref, "ToleranceItem",
                                     singular_tolerance: :last)
      end.to raise_error(ArgumentError, /singular_tolerance: :last/)
    end
  end

  describe "#tolerates_singular_overflow?" do
    let(:tolerant) do
      Lutaml::Model::Attribute.new(:ref, "ToleranceItem",
                                   singular_tolerance: :first)
    end

    let(:strict) { Lutaml::Model::Attribute.new(:ref, "ToleranceItem") }

    let(:collection_attr) do
      Lutaml::Model::Attribute.new(:refs, "ToleranceItem",
                                   collection: true,
                                   singular_tolerance: :first)
    end

    it "is true for an over-ingested collection on a tolerant singular" do
      expect(tolerant.tolerates_singular_overflow?([1, 2])).to be(true)
    end

    it "is false without the option" do
      expect(strict.tolerates_singular_overflow?([1, 2])).to be(false)
    end

    it "is false for a scalar on a tolerant singular" do
      expect(tolerant.tolerates_singular_overflow?(1)).to be(false)
    end

    it "is false for a collection attribute — the option does not apply" do
      expect(collection_attr.tolerates_singular_overflow?([1, 2])).to be(false)
    end
  end

  describe "strict default" do
    it "still raises CollectionTrueMissingError on over-ingest" do
      attr = Lutaml::Model::Attribute.new(:ref, "ToleranceItem")

      expect do
        attr.valid_collection!([item_class.new, item_class.new], String)
      end.to raise_error(Lutaml::Model::CollectionTrueMissingError)
    end
  end

  describe "tolerant ingest" do
    it "lets valid_collection! pass after the transform reduces to first" do
      attr = Lutaml::Model::Attribute.new(:ref, "ToleranceItem",
                                          singular_tolerance: :first)
      value = [item_class.new, item_class.new]

      reduced = value.first if attr.tolerates_singular_overflow?(value)
      expect(attr.valid_collection!(reduced, String)).to be(true)
      expect(reduced).to eq(value.first)
    end
  end
end
