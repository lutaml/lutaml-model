# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Type subclass facet restrictions" do
  describe "Layer-2 inclusive on an Integer subclass" do
    before do
      stub_const("Percentage", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 0, max: 100
      end)
      stub_const("Score", Class.new(Lutaml::Model::Serializable) do
        attribute :value, Percentage
      end)
    end

    it "passes for an in-range value" do
      expect(Score.new(value: 50).validate).to be_empty
    end

    it "collects a MinInclusiveError below the minimum" do
      expect(Score.new(value: -1).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "collects a MaxInclusiveError above the maximum" do
      expect(Score.new(value: 150).validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end

    it "does not raise until validate! (lazy)" do
      expect { Score.new(value: 999) }.not_to raise_error
    end
  end

  describe "Layer-2 length on a String subclass" do
    before do
      stub_const("Username", Class.new(Lutaml::Model::Type::String) do
        length min: 3, max: 8
      end)
      stub_const("Account", Class.new(Lutaml::Model::Serializable) do
        attribute :name, Username
      end)
    end

    it "passes for an in-range length" do
      expect(Account.new(name: "john").validate).to be_empty
    end

    it "rejects values shorter than the minimum length" do
      expect(Account.new(name: "jo").validate.first)
        .to be_a(Lutaml::Model::MinLengthError)
    end

    it "rejects values longer than the maximum length" do
      expect(Account.new(name: "jonathan_doe").validate.first)
        .to be_a(Lutaml::Model::MaxLengthError)
    end
  end

  describe "exact length facet" do
    before do
      stub_const("CountryCode", Class.new(Lutaml::Model::Type::String) do
        length 2
      end)
      stub_const("Place", Class.new(Lutaml::Model::Serializable) do
        attribute :code, CountryCode
      end)
    end

    it "passes when the length matches exactly" do
      expect(Place.new(code: "us").validate).to be_empty
    end

    it "collects a LengthError when the length differs" do
      expect(Place.new(code: "usa").validate.first)
        .to be_a(Lutaml::Model::LengthError)
    end

    it "rejects combining exact length with min:/max:" do
      expect do
        Class.new(Lutaml::Model::Type::String) { length 2, min: 1 }
      end.to raise_error(ArgumentError, /cannot be combined/)
    end
  end

  describe "Layer-1 and Layer-2 merge (tightest wins)" do
    before do
      stub_const("Percentage", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 0, max: 100
      end)
      stub_const("Capped", Class.new(Lutaml::Model::Serializable) do
        attribute :pct, Percentage, max: 90
      end)
    end

    it "accepts a value within the tighter bound" do
      expect(Capped.new(pct: 90).validate).to be_empty
    end

    it "rejects a value the type alone would allow" do
      expect(Capped.new(pct: 95).validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end

    it "still enforces the type's lower bound" do
      expect(Capped.new(pct: -1).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "raises a configuration error for a contradictory merge" do
      stub_const("HighFloor", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 50, max: 100
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :x, HighFloor, max: 40
      end

      expect { model.new(x: 45).validate }
        .to raise_error(ArgumentError, /exceeds/)
    end

    it "raises for a contradictory length merge" do
      stub_const("MidLen", Class.new(Lutaml::Model::Type::String) do
        length min: 10, max: 20
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :s, MidLen, max_length: 5
      end

      expect { model.new(s: "abc").validate }
        .to raise_error(ArgumentError, /exceeds/)
    end

    it "raises when an exact length falls outside a merged length range" do
      stub_const("FiveChars", Class.new(Lutaml::Model::Type::String) do
        length 5
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :s, FiveChars, min_length: 10
      end

      expect { model.new(s: "abcde").validate }
        .to raise_error(ArgumentError, /length \(5\) is outside/)
    end
  end

  describe "facet inheritance" do
    before do
      stub_const("BasePct", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 0, max: 100
      end)
    end

    it "lets a child tighten an inherited bound" do
      stub_const("TightPct", Class.new(BasePct) { inclusive max: 50 })

      expect(TightPct.facets).to eq(min_inclusive: 0, max_inclusive: 50)
    end

    it "raises when a child tries to widen an inherited bound" do
      wide = Class.new(BasePct) { inclusive max: 200 }

      expect { wide.facets }.to raise_error(ArgumentError, /cannot widen/)
    end

    it "isolates sibling subclasses" do
      a = Class.new(BasePct) { inclusive max: 50 }
      b = Class.new(BasePct)

      expect(a.facets).to eq(min_inclusive: 0, max_inclusive: 50)
      expect(b.facets).to eq(min_inclusive: 0, max_inclusive: 100)
    end

    it "rejects declaring a facet on an already-subclassed parent" do
      Class.new(BasePct)

      expect { BasePct.inclusive(min: 5) }
        .to raise_error(ArgumentError, /already has subclasses/)
    end

    it "closes a facet-less parent once it is subclassed" do
      stub_const("PlainInt", Class.new(Lutaml::Model::Type::Integer))
      Class.new(PlainInt)

      expect { PlainInt.inclusive(min: 0) }
        .to raise_error(ArgumentError, /already has subclasses/)
    end
  end

  describe "applicability guard on the merged facet set" do
    it "rejects a length facet on a numeric subclass" do
      stub_const("BadInt", Class.new(Lutaml::Model::Type::Integer) do
        length min: 1, max: 5
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :x, BadInt
      end

      expect { model.new(x: 3).validate }
        .to raise_error(ArgumentError, /only allowed for :string type/)
    end

    it "rejects an inclusive facet on a string subclass" do
      stub_const("BadStr", Class.new(Lutaml::Model::Type::String) do
        inclusive min: 0, max: 10
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :s, BadStr
      end

      expect { model.new(s: "a").validate }
        .to raise_error(ArgumentError, /only allowed for numeric types/)
    end
  end

  describe "same-class facet re-declaration" do
    it "keeps the tighter bound when a key is declared twice" do
      stub_const("DoubleDecl", Class.new(Lutaml::Model::Type::Integer) do
        inclusive max: 100
        inclusive max: 200
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, DoubleDecl
      end

      expect(DoubleDecl.facets).to eq(max_inclusive: 100)
      expect(model.new(n: 150).validate.first)
        .to be_a(Lutaml::Model::MaxInclusiveError)
    end

    it "raises when a different exact length is re-declared" do
      expect do
        Class.new(Lutaml::Model::Type::String) do
          length 5
          length 3
        end
      end.to raise_error(ArgumentError, /conflicting `length`/)
    end
  end

  describe "Layer-2 exclusive on an Integer subclass" do
    before do
      stub_const("OpenRange", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 0, max: 100
      end)
      stub_const("Reading", Class.new(Lutaml::Model::Serializable) do
        attribute :value, OpenRange
      end)
    end

    it "passes for a value strictly inside the bounds" do
      expect(Reading.new(value: 50).validate).to be_empty
    end

    it "collects a MinExclusiveError at the lower bound" do
      expect(Reading.new(value: 0).validate.first)
        .to be_a(Lutaml::Model::MinExclusiveError)
    end

    it "collects a MaxExclusiveError at the upper bound" do
      expect(Reading.new(value: 100).validate.first)
        .to be_a(Lutaml::Model::MaxExclusiveError)
    end

    it "does not raise until validate! (lazy)" do
      expect { Reading.new(value: 0) }.not_to raise_error
    end
  end

  describe "ordered facets on temporal types" do
    it "enforces inclusive bounds on a Date subclass" do
      stub_const("Era", Class.new(Lutaml::Model::Type::Date) do
        inclusive min: Date.new(2000, 1, 1), max: Date.new(2020, 12, 31)
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :day, Era
      end

      expect(model.new(day: "2010-06-15").validate).to be_empty
      expect(model.new(day: "2000-01-01").validate).to be_empty
      expect(model.new(day: "1999-12-31").validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "enforces exclusive bounds on a Date subclass" do
      stub_const("OpenEra", Class.new(Lutaml::Model::Type::Date) do
        exclusive min: Date.new(2000, 1, 1), max: Date.new(2020, 1, 1)
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :day, OpenEra
      end

      expect(model.new(day: "2010-06-15").validate).to be_empty
      expect(model.new(day: "2000-01-01").validate.first)
        .to be_a(Lutaml::Model::MinExclusiveError)
      expect(model.new(day: "2020-01-01").validate.first)
        .to be_a(Lutaml::Model::MaxExclusiveError)
    end
  end

  describe "exclusive facet inheritance and merge" do
    it "lets a child tighten an inherited exclusive bound" do
      stub_const("BaseOpen", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 0, max: 100
      end)
      tight = Class.new(BaseOpen) { exclusive max: 50 }

      expect(tight.facets).to eq(min_exclusive: 0, max_exclusive: 50)
    end

    it "raises when a child widens an inherited exclusive bound" do
      stub_const("BaseOpen", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 0, max: 100
      end)
      wide = Class.new(BaseOpen) { exclusive max: 200 }

      expect { wide.facets }.to raise_error(ArgumentError, /cannot widen/)
    end

    it "keeps the tighter bound when an exclusive key is declared twice" do
      stub_const("DoubleOpen", Class.new(Lutaml::Model::Type::Integer) do
        exclusive max: 100
        exclusive max: 200
      end)

      expect(DoubleOpen.facets).to eq(max_exclusive: 100)
    end
  end

  describe "interval consistency across inclusive and exclusive bounds" do
    it "rejects an empty interval when one bound is exclusive" do
      stub_const("Empty", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 5
        exclusive max: 5
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, Empty
      end

      expect { model.new(n: 5).validate }
        .to raise_error(ArgumentError, /empty interval/)
    end

    it "accepts a non-empty interval between two exclusive bounds" do
      stub_const("Narrow", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 5
        exclusive max: 6
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, Narrow
      end

      expect { model.new(n: 6).validate }.not_to raise_error
    end

    it "consolidates same-side inclusive+exclusive to the tighter (inclusive) bound" do
      stub_const("Tightened", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: 5
        exclusive min: 3
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, Tightened
      end

      expect(model.new(n: 5).validate).to be_empty
      expect(model.new(n: 4).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "consolidates a cross-layer min pair, inclusive winning when tighter" do
      stub_const("OpenFloor", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 3
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, OpenFloor, min: 5
      end

      expect(model.new(n: 5).validate).to be_empty
      expect(model.new(n: 4).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "consolidates a cross-layer min pair, exclusive winning (and on ties)" do
      stub_const("TightFloor", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 5
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, TightFloor, min: 3
      end

      expect(model.new(n: 6).validate).to be_empty
      expect(model.new(n: 5).validate.first)
        .to be_a(Lutaml::Model::MinExclusiveError)
    end

    it "consolidates a cross-layer max pair to the tighter bound" do
      stub_const("Capped", Class.new(Lutaml::Model::Type::Integer) do
        exclusive max: 8
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, Capped, max: 10
      end

      expect(model.new(n: 7).validate).to be_empty
      expect(model.new(n: 8).validate.first)
        .to be_a(Lutaml::Model::MaxExclusiveError)
    end

    # An explicit `min: nil` must not add a nil facet that makes consolidation
    # bail out and hide a genuinely empty interval declared on the type.
    it "still flags an empty interval when a nil option bound is present" do
      stub_const("EmptyRange", Class.new(Lutaml::Model::Type::Integer) do
        exclusive min: 5
        inclusive max: 5
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, EmptyRange, min: nil
      end

      expect { model.new(n: 5).validate }
        .to raise_error(ArgumentError, /empty interval/)
    end
  end

  describe "applicability of ordered facets" do
    it "rejects an exclusive facet on a string subclass" do
      stub_const("BadOpen", Class.new(Lutaml::Model::Type::String) do
        exclusive min: 0, max: 10
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :s, BadOpen
      end

      expect { model.new(s: "a").validate }
        .to raise_error(ArgumentError, /numeric types or temporal/)
    end

    it "accepts ordered facets on a temporal subclass" do
      stub_const("BoundedDay", Class.new(Lutaml::Model::Type::Date) do
        inclusive min: Date.new(2000, 1, 1)
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :day, BoundedDay
      end

      expect { model.new(day: "2010-01-01").validate }.not_to raise_error
    end
  end

  describe "Layer-2 enumeration on a String subclass" do
    before do
      stub_const("Status", Class.new(Lutaml::Model::Type::String) do
        enumeration "active", "inactive", "archived"
      end)
      stub_const("Ticket", Class.new(Lutaml::Model::Serializable) do
        attribute :state, Status
      end)
    end

    it "passes for an allowed value" do
      expect(Ticket.new(state: "active").validate).to be_empty
    end

    it "collects an InvalidValueError for a value outside the set" do
      expect(Ticket.new(state: "deleted").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "rejects the empty string when it is not enumerated" do
      expect(Ticket.new(state: "").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "does not raise until validate! (lazy)" do
      expect { Ticket.new(state: "deleted") }.not_to raise_error
    end
  end

  describe "Layer-2 facet values are cast at declaration (issue #191)" do
    it "orders repeated string bounds numerically, not lexically" do
      stub_const("Repeated", Class.new(Lutaml::Model::Type::Integer) do
        inclusive min: "9"
        inclusive min: "10"
      end)
      model = Class.new(Lutaml::Model::Serializable) { attribute :n, Repeated }

      expect(model.new(n: 10).validate).to be_empty
      expect(model.new(n: 9).validate.first)
        .to be_a(Lutaml::Model::MinInclusiveError)
    end

    it "raises at declaration for a facet value the type cannot cast" do
      expect do
        Class.new(Lutaml::Model::Type::Integer) { inclusive min: "abc" }
      end.to raise_error(ArgumentError, /not castable/)
    end
  end

  describe "enumeration members declared as strings are cast (issue #191)" do
    it "matches an Integer value against string-declared enumeration members" do
      stub_const("Digit", Class.new(Lutaml::Model::Type::Integer) do
        enumeration "1", "2"
      end)
      model = Class.new(Lutaml::Model::Serializable) { attribute :d, Digit }

      expect(model.new(d: 1).validate).to be_empty
      expect(model.new(d: 3).validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "matches a Decimal value against string-declared enumeration members" do
      stub_const("Rate", Class.new(Lutaml::Model::Type::Decimal) do
        enumeration "1.5", "2.5"
      end)
      model = Class.new(Lutaml::Model::Serializable) { attribute :r, Rate }

      expect(model.new(r: "1.5").validate).to be_empty
      expect(model.new(r: "9.9").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end
  end

  describe "enumeration intersection across inheritance" do
    before do
      stub_const("BaseStatus", Class.new(Lutaml::Model::Type::String) do
        enumeration "active", "inactive", "archived"
      end)
    end

    it "narrows the allowed set in a subclass (intersection)" do
      stub_const("LiveStatus", Class.new(BaseStatus) do
        enumeration "active", "inactive"
      end)

      expect(LiveStatus.facets).to eq(enumeration: %w[active inactive])
    end

    it "rejects a value the parent allows but the child excludes" do
      stub_const("LiveStatus", Class.new(BaseStatus) do
        enumeration "active", "inactive"
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :state, LiveStatus
      end

      expect(model.new(state: "active").validate).to be_empty
      expect(model.new(state: "archived").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "raises when a child introduces a value outside the parent set" do
      widen = Class.new(BaseStatus) { enumeration "active", "deleted" }

      expect { widen.facets }.to raise_error(ArgumentError, /cannot widen/)
    end

    it "raises a config error for an empty intersection (same class)" do
      stub_const("Disjoint", Class.new(Lutaml::Model::Type::String) do
        enumeration "a", "b"
        enumeration "c", "d"
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :s, Disjoint
      end

      expect { model.new(s: "a").validate }
        .to raise_error(ArgumentError, /enumeration/)
    end
  end

  describe "Layer-2 pattern on a String subclass" do
    before do
      stub_const("Code", Class.new(Lutaml::Model::Type::String) do
        pattern '\A[A-Z]{3}\z'
      end)
      stub_const("Item", Class.new(Lutaml::Model::Serializable) do
        attribute :code, Code
      end)
    end

    it "passes for a matching value" do
      expect(Item.new(code: "ABC").validate).to be_empty
    end

    it "collects a PatternNotMatchedError for a non-matching value" do
      expect(Item.new(code: "ab").validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
    end

    it "rejects the empty string" do
      expect(Item.new(code: "").validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
    end

    it "does not raise until validate! (lazy)" do
      expect { Item.new(code: "ab") }.not_to raise_error
    end
  end

  describe "pattern accumulation across inheritance" do
    it "requires a value to match every pattern in the chain" do
      stub_const("Alpha", Class.new(Lutaml::Model::Type::String) do
        pattern '\A[A-Za-z]+\z'
      end)
      stub_const("ShortAlpha", Class.new(Alpha) do
        pattern '\A.{1,3}\z'
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :s, ShortAlpha
      end

      expect(model.new(s: "abc").validate).to be_empty
      expect(model.new(s: "abcd").validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
      expect(model.new(s: "12").validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
    end
  end

  describe "applicability of the pattern facet" do
    it "rejects a pattern facet on a non-string subclass" do
      stub_const("BadNum", Class.new(Lutaml::Model::Type::Integer) do
        pattern '\A[0-9]+\z'
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :n, BadNum
      end

      expect { model.new(n: 5).validate }
        .to raise_error(ArgumentError, /pattern.*string/)
    end
  end

  describe "Layer-2 facets coexist with Layer-1 options" do
    it "applies both a Layer-1 values: option and a Layer-2 enumeration" do
      stub_const("Status", Class.new(Lutaml::Model::Type::String) do
        enumeration "active", "inactive", "archived"
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :state, Status, values: %w[active inactive]
      end

      expect(model.new(state: "active").validate).to be_empty
      expect(model.new(state: "archived").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
      expect(model.new(state: "deleted").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end

    it "applies both a Layer-1 values: option and a Layer-2 pattern" do
      stub_const("Code", Class.new(Lutaml::Model::Type::String) do
        pattern '\A[A-Z]{3}\z'
      end)
      model = Class.new(Lutaml::Model::Serializable) do
        attribute :code, Code, values: %w[ABC XY]
      end

      expect(model.new(code: "ABC").validate).to be_empty
      # "XY" satisfies the Layer-1 values: list but not the Layer-2 pattern,
      # proving the Layer-2 facet is enforced in addition to the option.
      expect(model.new(code: "XY").validate.first)
        .to be_a(Lutaml::Model::PatternNotMatchedError)
      expect(model.new(code: "DEF").validate.first)
        .to be_a(Lutaml::Model::InvalidValueError)
    end
  end
end
