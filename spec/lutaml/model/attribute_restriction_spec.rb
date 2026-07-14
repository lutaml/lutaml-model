# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attribute value restrictions" do
  describe "numeric min/max bounds" do
    before do
      stub_const("BoundedInteger", Class.new(Lutaml::Model::Serializable) do
        attribute :age, :integer, min: 0, max: 120
      end)
    end

    it "passes validation for a value within the range" do
      expect(BoundedInteger.new(age: 30).validate).to be_empty
    end

    it "collects a MinInclusiveError when below the minimum" do
      instance = BoundedInteger.new(age: -1)
      errors = instance.validate

      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(Lutaml::Model::MinInclusiveError)
      expect(errors.first.to_s).to include("age")
    end

    it "collects a MaxInclusiveError when above the maximum" do
      instance = BoundedInteger.new(age: 200)
      errors = instance.validate

      expect(errors.first).to be_a(Lutaml::Model::MaxInclusiveError)
    end

    it "raises ValidationError from validate! for an out-of-range value" do
      instance = BoundedInteger.new(age: -1)

      expect { instance.validate! }
        .to raise_error(Lutaml::Model::ValidationError)
    end
  end

  describe "numeric bounds across numeric types" do
    it "enforces bounds on Decimal values" do
      stub_const("BoundedDecimal", Class.new(Lutaml::Model::Serializable) do
        attribute :score, :decimal, min: 0, max: 100
      end)

      expect(BoundedDecimal.new(score: 50).validate).to be_empty
      expect(BoundedDecimal.new(score: 150).validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end

    it "enforces bounds on Float values" do
      stub_const("BoundedFloat", Class.new(Lutaml::Model::Serializable) do
        attribute :ratio, :float, min: 0.0, max: 1.0
      end)

      expect(BoundedFloat.new(ratio: 0.5).validate).to be_empty
      expect(BoundedFloat.new(ratio: 1.5).validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end
  end

  describe "signed: false" do
    before do
      stub_const("UnsignedInteger", Class.new(Lutaml::Model::Serializable) do
        attribute :count, :integer, signed: false
      end)
    end

    it "accepts zero" do
      expect(UnsignedInteger.new(count: 0).validate).to be_empty
    end

    it "accepts positive values" do
      expect(UnsignedInteger.new(count: 42).validate).to be_empty
    end

    it "rejects negative values" do
      expect(UnsignedInteger.new(count: -1).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "merges with an explicit min by taking the greater bound" do
      stub_const("FlooredInteger", Class.new(Lutaml::Model::Serializable) do
        attribute :count, :integer, min: -10, signed: false
      end)

      expect(FlooredInteger.new(count: 0).validate).to be_empty
      expect(FlooredInteger.new(count: -1).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end
  end

  describe "temporal bounds (Layer 1)" do
    before do
      stub_const("DatedEvent", Class.new(Lutaml::Model::Serializable) do
        attribute :on, :date,
                  min: Date.new(2000, 1, 1), max: Date.new(2020, 12, 31)
      end)
    end

    it "passes for a date within the range" do
      expect(DatedEvent.new(on: "2010-06-15").validate).to be_empty
    end

    it "collects a MinInclusiveError before the minimum date" do
      expect(DatedEvent.new(on: "1999-12-31").validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "collects a MaxInclusiveError after the maximum date" do
      expect(DatedEvent.new(on: "2021-01-01").validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end
  end

  describe "string length bounds" do
    before do
      stub_const("BoundedString", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string, min_length: 1, max_length: 5
      end)
    end

    it "passes validation for a length within the range" do
      expect(BoundedString.new(name: "abc").validate).to be_empty
    end

    it "rejects a value shorter than min_length" do
      expect(BoundedString.new(name: "").validate.first)
        .to be_a(Lutaml::Model::MinLengthError)
    end

    it "rejects a value longer than max_length" do
      expect(BoundedString.new(name: "abcdef").validate.first)
        .to be_a(Lutaml::Model::MaxLengthError)
    end

    it "rejects the empty string when min_length is 1" do
      errors = BoundedString.new(name: "").validate

      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(Lutaml::Model::MinLengthError)
    end
  end

  describe "length bounds on a non-::String string-derived type (issue #191)" do
    # Type::Uri is string-derived (Uri < String) but its cast value is a ::URI,
    # which has no #length. Length facets must measure the lexical (serialized)
    # form, not the raw cast object, or validation crashes with NoMethodError.
    it "measures the lexical form and passes a URI within range" do
      stub_const("UriInRange", Class.new(Lutaml::Model::Serializable) do
        attribute :homepage, :uri, min_length: 5, max_length: 100
      end)

      instance = UriInRange.new(homepage: URI.parse("http://example.com"))

      expect(instance.validate).to be_empty
    end

    it "collects a MaxLengthError (never NoMethodError) for a too-long URI" do
      stub_const("UriTooLong", Class.new(Lutaml::Model::Serializable) do
        attribute :homepage, :uri, max_length: 5
      end)

      instance = UriTooLong.new(homepage: URI.parse("http://example.com"))

      expect(instance.validate.first).to be_a(Lutaml::Model::MaxLengthError)
    end

    it "renders the length error message without crashing on the ::URI value" do
      stub_const("UriTooLong", Class.new(Lutaml::Model::Serializable) do
        attribute :homepage, :uri, max_length: 5
      end)

      instance = UriTooLong.new(homepage: URI.parse("http://example.com"))

      expect { instance.validate! }
        .to raise_error(Lutaml::Model::ValidationError, /homepage/)
    end
  end

  describe "lazy validation" do
    before do
      stub_const("LazyModel", Class.new(Lutaml::Model::Serializable) do
        attribute :age, :integer, min: 0, max: 120
        attribute :name, :string, min_length: 1
      end)
    end

    it "does not raise when an out-of-range value is assigned" do
      expect { LazyModel.new(age: -5, name: "") }.not_to raise_error
    end

    it "only surfaces the error on validate!" do
      instance = LazyModel.new(age: -5, name: "ok")

      expect { instance.validate! }
        .to raise_error(Lutaml::Model::ValidationError)
    end
  end

  describe "configuration guards" do
    it "rejects numeric bounds on a string attribute" do
      stub_const("MisconfiguredString", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string, min: 0
      end)

      expect { MisconfiguredString.new(name: "a").validate }
        .to raise_error(ArgumentError, /only allowed for numeric types/)
    end

    it "rejects length bounds on a numeric attribute" do
      stub_const("MisconfiguredInteger", Class.new(Lutaml::Model::Serializable) do
        attribute :age, :integer, min_length: 1
      end)

      expect { MisconfiguredInteger.new(age: 1).validate }
        .to raise_error(ArgumentError, /only allowed for :string type/)
    end

    it "rejects signed: true on a string attribute" do
      stub_const("SignedString", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string, signed: true
      end)

      expect { SignedString.new(name: "a").validate }
        .to raise_error(ArgumentError, /only allowed for numeric types/)
    end

    it "treats signed: true on a numeric attribute as a no-op" do
      stub_const("SignedInteger", Class.new(Lutaml::Model::Serializable) do
        attribute :count, :integer, signed: true
      end)

      expect(SignedInteger.new(count: -5).validate).to be_empty
      expect { SignedInteger.new(count: -5).validate! }.not_to raise_error
    end

    it "accepts negative values when signed is not given (signed defaults to true)" do
      stub_const("DefaultInteger", Class.new(Lutaml::Model::Serializable) do
        attribute :count, :integer
      end)

      expect(DefaultInteger.new(count: -5).validate).to be_empty
    end

    it "rejects a negative min_length at attribute definition" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string, min_length: -1
        end
      end.to raise_error(ArgumentError,
                         /`min_length` must be a non-negative Integer/)
    end

    it "rejects a negative max_length at attribute definition" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string, max_length: -1
        end
      end.to raise_error(ArgumentError,
                         /`max_length` must be a non-negative Integer/)
    end

    it "rejects a non-Integer min_length at attribute definition" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string, min_length: "5"
        end
      end.to raise_error(ArgumentError,
                         /`min_length` must be a non-negative Integer/)
    end

    it "rejects a Float max_length at attribute definition" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string, max_length: 2.5
        end
      end.to raise_error(ArgumentError,
                         /`max_length` must be a non-negative Integer/)
    end

    it "rejects a non-boolean signed at attribute definition" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :count, :integer, signed: "false"
        end
      end.to raise_error(ArgumentError, /`signed` must be true or false/)
    end

    it "accepts signed: false at attribute definition" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :count, :integer, signed: false
        end
      end.not_to raise_error
    end
  end

  describe "collections (per-element restrictions)" do
    before do
      stub_const("BoundedCollection", Class.new(Lutaml::Model::Serializable) do
        attribute :ages, :integer, collection: true, min: 0
      end)
    end

    it "passes when every element satisfies a Layer-1 numeric bound" do
      expect(BoundedCollection.new(ages: [0, 5, 120]).validate).to be_empty
    end

    it "collects a MinInclusiveError when an element violates the bound" do
      errors = BoundedCollection.new(ages: [1, -5, 10]).validate

      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "raises from validate! when an element is out of range" do
      expect { BoundedCollection.new(ages: [1, -5]).validate! }
        .to raise_error(Lutaml::Model::ValidationError)
    end

    it "skips nil elements, checking only present ones" do
      expect(BoundedCollection.new(ages: [nil, 5]).validate).to be_empty
      expect(BoundedCollection.new(ages: [nil, -5]).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "applies the facet to a scalar assigned to a collection attribute" do
      expect(BoundedCollection.new(ages: 5).validate).to be_empty
      expect(BoundedCollection.new(ages: -5).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "enforces a Layer-2 inclusive facet per element" do
      stub_const("Percentage", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 0, max: 100
      end)
      stub_const("Report", Class.new(Lutaml::Model::Serializable) do
        attribute :scores, Percentage, collection: true
      end)

      expect(Report.new(scores: [10, 50, 100]).validate).to be_empty
      expect(Report.new(scores: [10, 150]).validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end

    it "enforces a Layer-1 min_length per string element" do
      stub_const("Names", Class.new(Lutaml::Model::Serializable) do
        attribute :tags, :string, collection: true, min_length: 2
      end)

      expect(Names.new(tags: %w[ab cde]).validate).to be_empty
      expect(Names.new(tags: %w[ab c]).validate.first)
        .to be_a(Lutaml::Model::MinLengthError)
    end

    it "enforces a Layer-2 pattern per string element" do
      stub_const("Code", Class.new(Lutaml::Model::Type::String) do
        pattern '\A[a-z]+\z'
      end)
      stub_const("Codes", Class.new(Lutaml::Model::Serializable) do
        attribute :list, Code, collection: true
      end)

      expect(Codes.new(list: %w[abc def]).validate).to be_empty
      expect(Codes.new(list: %w[abc DEF]).validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
    end

    it "enforces a Layer-2 enumeration per element" do
      stub_const("Status", Class.new(Lutaml::Model::Type::String) do
        enumeration "active", "inactive"
      end)
      stub_const("Flags", Class.new(Lutaml::Model::Serializable) do
        attribute :states, Status, collection: true
      end)

      expect(Flags.new(states: %w[active inactive]).validate).to be_empty
      expect(Flags.new(states: %w[active deleted]).validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "enforces a digit facet per element" do
      stub_const("Money", Class.new(Lutaml::Model::Type::Decimal) do
        total_digits 5
      end)
      stub_const("Ledger", Class.new(Lutaml::Model::Serializable) do
        attribute :amounts, Money, collection: true
      end)

      expect(Ledger.new(amounts: ["12.34", "1.5"]).validate).to be_empty
      expect(Ledger.new(amounts: ["12.34", "123456"]).validate.first)
        .to be_a(Lutaml::Model::TotalDigitsError)
    end

    it "governs item count via the collection range, not the length facet" do
      stub_const("Sized", Class.new(Lutaml::Model::Serializable) do
        attribute :list, :string, collection: 2..3, min_length: 3
      end)

      expect(Sized.new(list: %w[abc def]).validate).to be_empty
      expect(Sized.new(list: %w[abc de]).validate.first)
        .to be_a(Lutaml::Model::MinLengthError)
      expect(Sized.new(list: %w[abc def ghi jkl]).validate.first)
        .to be_a(Lutaml::Model::CollectionCountOutOfRangeError)
    end
  end

  describe "backward compatibility" do
    it "keeps values: enumeration validation working" do
      stub_const("EnumModel", Class.new(Lutaml::Model::Serializable) do
        attribute :status, :string, values: %w[active inactive]
      end)

      expect(EnumModel.new(status: "active").validate).to be_empty
      expect(EnumModel.new(status: "unknown").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "keeps pattern: validation working" do
      stub_const("PatternModel", Class.new(Lutaml::Model::Serializable) do
        attribute :code, :string, pattern: /\A[a-z]+\z/
      end)

      expect(PatternModel.new(code: "abc").validate).to be_empty
      expect(PatternModel.new(code: "ABC").validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
    end
  end
end
