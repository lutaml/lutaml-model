# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe "totalDigits / fractionDigits facets" do
  def build_model(base, total: nil, fraction: nil)
    type = Class.new(base)
    type.total_digits(total) unless total.nil?
    type.fraction_digits(fraction) unless fraction.nil?
    Class.new(Lutaml::Model::Serializable) do
      attribute :n, type
    end
  end

  def errors_for(base, value, total: nil, fraction: nil)
    build_model(base, total: total, fraction: fraction).new(n: value).validate
  end

  let(:decimal) { Lutaml::Model::Type::Decimal }
  let(:integer) { Lutaml::Model::Type::Integer }

  describe "digit counting convention" do
    # base, lexical value, expected total digits, expected fraction digits
    [
      [Lutaml::Model::Type::Decimal, "123.45", 5, 2],
      [Lutaml::Model::Type::Decimal, "100", 3, 0],
      [Lutaml::Model::Type::Decimal, "0.1", 1, 1],
      [Lutaml::Model::Type::Decimal, "0.100", 1, 1],
      [Lutaml::Model::Type::Decimal, "100.00", 3, 0],
      [Lutaml::Model::Type::Decimal, "-123.45", 5, 2],
      [Lutaml::Model::Type::Decimal, "12.340", 4, 2],
      [Lutaml::Model::Type::Decimal, "0.05", 1, 2],
      [Lutaml::Model::Type::Decimal, "0.001", 1, 3],
      [Lutaml::Model::Type::Decimal, "0.5", 1, 1],
      [Lutaml::Model::Type::Integer, 12345, 5, 0],
    ].each do |base, value, total, fraction|
      it "counts #{value.inspect} as #{total} total / #{fraction} fraction" do
        expect(errors_for(base, value, total: total)).to be_empty
        expect(errors_for(base, value, fraction: fraction)).to be_empty

        if total > 1
          expect(errors_for(base, value, total: total - 1).first)
            .to be_a(Lutaml::Model::TotalDigitsError)
        end
        if fraction.positive?
          expect(errors_for(base, value, fraction: fraction - 1).first)
            .to be_a(Lutaml::Model::FractionDigitsError)
        end
      end
    end

    it "counts only significant digits toward the total (XSD)" do
      # `0.05` has one significant digit (`5`), so a `total_digits 1` type
      # accepts it: the leading zero before the point is insignificant. This
      # is required for XSD round-trip conformance -- a model generated from
      # `<xs:totalDigits value="1"/>` must accept 0.05 and reject 12.
      model = build_model(decimal, total: 1)

      expect(model.new(n: "0.05").validate).to be_empty
      expect(model.new(n: "12").validate.first)
        .to be_a(Lutaml::Model::TotalDigitsError)
    end

    it "treats integer zero as zero significant digits" do
      expect(errors_for(integer, 0, total: 1)).to be_empty
      expect(errors_for(integer, 0, fraction: 0)).to be_empty
    end

    it "treats decimal zero as zero significant digits" do
      expect(errors_for(decimal, "0", total: 1)).to be_empty
      expect(errors_for(decimal, "0.0", fraction: 0)).to be_empty
    end
  end

  describe "total_digits enforcement" do
    it "passes a Decimal within the digit budget" do
      expect(errors_for(decimal, "123.45", total: 8)).to be_empty
    end

    it "collects a TotalDigitsError when a Decimal exceeds the budget" do
      expect(errors_for(decimal, "123.456", total: 5).first)
        .to be_a(Lutaml::Model::TotalDigitsError)
    end

    it "passes an Integer within the digit budget" do
      expect(errors_for(integer, 12345, total: 5)).to be_empty
    end

    it "collects a TotalDigitsError when an Integer exceeds the budget" do
      expect(errors_for(integer, 123456, total: 5).first)
        .to be_a(Lutaml::Model::TotalDigitsError)
    end
  end

  describe "fraction_digits enforcement" do
    it "passes a Decimal within the fraction budget" do
      expect(errors_for(decimal, "1.23", fraction: 2)).to be_empty
    end

    it "collects a FractionDigitsError when the fraction is too long" do
      expect(errors_for(decimal, "1.234", fraction: 2).first)
        .to be_a(Lutaml::Model::FractionDigitsError)
    end

    it "enforces both facets together (Money-style)" do
      model = build_model(decimal, total: 8, fraction: 2)

      expect(model.new(n: "123456.78").validate).to be_empty
      expect(model.new(n: "1234567.89").validate.first)
        .to be_a(Lutaml::Model::TotalDigitsError)
      expect(model.new(n: "1.234").validate.first)
        .to be_a(Lutaml::Model::FractionDigitsError)
    end
  end

  describe "laziness" do
    it "does not raise until validate!" do
      model = build_model(decimal, total: 3)

      expect { model.new(n: "123456") }.not_to raise_error
      expect(model.new(n: "123456").validate.first)
        .to be_a(Lutaml::Model::TotalDigitsError)
    end
  end

  describe "declaration guards" do
    it "rejects a negative total_digits" do
      expect { Class.new(decimal) { total_digits(-1) } }
        .to raise_error(ArgumentError)
    end

    it "rejects total_digits 0" do
      expect { Class.new(decimal) { total_digits 0 } }
        .to raise_error(ArgumentError)
    end

    it "rejects a non-integer total_digits" do
      expect { Class.new(decimal) { total_digits 2.5 } }
        .to raise_error(ArgumentError)
    end

    it "rejects a negative fraction_digits" do
      expect { Class.new(decimal) { fraction_digits(-1) } }
        .to raise_error(ArgumentError)
    end

    it "allows fraction_digits 0" do
      expect { Class.new(decimal) { fraction_digits 0 } }.not_to raise_error
    end
  end

  describe "applicability guard" do
    it "rejects digit facets on a Float subclass" do
      expect { errors_for(Lutaml::Model::Type::Float, 1.5, total: 5) }
        .to raise_error(ArgumentError, /:integer and :decimal/)
    end

    it "rejects digit facets on a String subclass" do
      expect { errors_for(Lutaml::Model::Type::String, "12", total: 5) }
        .to raise_error(ArgumentError, /:integer and :decimal/)
    end

    it "rejects digit facets on a temporal subclass" do
      expect do
        errors_for(Lutaml::Model::Type::Date, "2020-01-01", total: 5)
      end.to raise_error(ArgumentError, /:integer and :decimal/)
    end
  end

  describe "consistency guard" do
    it "rejects fraction_digits exceeding total_digits" do
      expect { errors_for(decimal, "1.5", total: 3, fraction: 5) }
        .to raise_error(ArgumentError, /fraction_digits.*exceeds.*total_digits/)
    end

    it "accepts fraction_digits equal to total_digits" do
      expect(errors_for(decimal, "0.12", total: 2, fraction: 2)).to be_empty
    end
  end

  describe "MAX-like merge and inheritance" do
    it "keeps the smaller total_digits when re-declared" do
      type = Class.new(decimal) do
        total_digits 8
        total_digits 5
      end

      expect(type.facets).to eq(total_digits: 5)
    end

    it "lets a child tighten total_digits" do
      base = Class.new(decimal) { total_digits 8 }
      child = Class.new(base) { total_digits 5 }

      expect(child.facets).to eq(total_digits: 5)
    end

    it "raises when a child widens total_digits" do
      base = Class.new(decimal) { total_digits 5 }
      child = Class.new(base) { total_digits 8 }

      expect { child.facets }.to raise_error(ArgumentError, /cannot widen/)
    end

    it "lets a child tighten fraction_digits" do
      base = Class.new(decimal) { fraction_digits 4 }
      child = Class.new(base) { fraction_digits 2 }

      expect(child.facets).to eq(fraction_digits: 2)
    end

    it "raises when a child widens fraction_digits" do
      base = Class.new(decimal) { fraction_digits 2 }
      child = Class.new(base) { fraction_digits 4 }

      expect { child.facets }.to raise_error(ArgumentError, /cannot widen/)
    end

    it "enforces the tightest inherited total_digits" do
      base = Class.new(decimal) { total_digits 8 }
      child = Class.new(base) { total_digits 6 }

      expect(errors_for(child, "12345.6")).to be_empty
      expect(errors_for(child, "1234567").first)
        .to be_a(Lutaml::Model::TotalDigitsError)
    end
  end
end
