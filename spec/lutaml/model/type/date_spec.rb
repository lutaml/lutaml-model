require "spec_helper"

RSpec.describe Lutaml::Model::Type::Date do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with valid Date string" do
      let(:value) { "2024-01-01" }

      it { is_expected.to eq(Date.new(2024, 1, 1)) }
    end

    context "with Date object" do
      let(:value) { Date.new(2024, 1, 1) }

      it { is_expected.to eq(value) }
    end

    context "with DateTime object" do
      let(:value) { DateTime.new(2024, 1, 1, 12, 0, 0) }

      it { is_expected.to eq(Date.new(2024, 1, 1)) }
    end

    context "with Time object" do
      let(:value) { Time.new(2024, 1, 1, 12, 0, 0) }

      it { is_expected.to eq(Date.new(2024, 1, 1)) }
    end

    context "with invalid date string" do
      let(:value) { "not a date" }

      it { is_expected.to be_nil }
    end

    context "with invalid month" do
      let(:value) { "2024-13-01" }

      it { is_expected.to be_nil }
    end

    context "with invalid day" do
      let(:value) { "2024-04-31" }

      it { is_expected.to be_nil }
    end

    context "with different date formats" do
      it "parses ISO 8601" do
        expect(described_class.cast("2024-01-01")).to eq(Date.new(2024, 1, 1))
      end

      it "parses RFC 3339" do
        expect(described_class.cast("2024-01-01T12:00:00Z")).to eq(Date.new(
                                                                     2024, 1, 1
                                                                   ))
      end

      it "parses common formats" do
        expect(described_class.cast("01/01/2024")).to eq(Date.new(2024, 1, 1))
        expect(described_class.cast("Jan 1, 2024")).to eq(Date.new(2024, 1, 1))
      end
    end

    context "with leap year dates" do
      it "handles February 29 in leap years" do
        expect(described_class.cast("2024-02-29")).to eq(Date.new(2024, 2, 29))
      end

      it "rejects February 29 in non-leap years" do
        expect(described_class.cast("2023-02-29")).to be_nil
      end
    end

    context "with timezone information" do
      it "preserves UTC timezone from Z suffix" do
        result = described_class.cast("2019-09-28Z")
        expect(result).to be_a(DateTime)
        expect(result.offset).to eq(Rational(0))
      end

      it "preserves positive timezone offset" do
        result = described_class.cast("2019-12-02+08:00")
        expect(result).to be_a(DateTime)
        expect(result.offset).to eq(Rational(8, 24))
        expect(result.month).to eq(12)
        expect(result.mday).to eq(2)
      end

      it "preserves negative timezone offset" do
        result = described_class.cast("2019-12-02-05:00")
        expect(result).to be_a(DateTime)
        expect(result.offset).to eq(Rational(-5, 24))
        expect(result.month).to eq(12)
        expect(result.mday).to eq(2)
      end

      it "preserves fractional timezone offset" do
        result = described_class.cast("2019-06-15+05:30")
        expect(result).to be_a(DateTime)
        expect(result.offset).to eq(Rational(5.5, 24))
      end

      it "returns plain Date for strings without timezone" do
        result = described_class.cast("2024-01-01")
        expect(result).to be_a(Date)
        expect(result).not_to be_a(DateTime)
      end
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with Date object" do
      let(:value) { Date.new(2024, 1, 1) }

      it { is_expected.to eq("2024-01-01") }
    end

    context "with single-digit month and day" do
      let(:value) { Date.new(2024, 1, 1) }

      it "zero-pads month and day" do
        expect(serialize).to eq("2024-01-01")
      end
    end

    context "with double-digit month and day" do
      let(:value) { Date.new(2024, 12, 31) }

      it { is_expected.to eq("2024-12-31") }
    end

    context "with leap year date" do
      let(:value) { Date.new(2024, 2, 29) }

      it { is_expected.to eq("2024-02-29") }
    end

    context "with UTC timezone (DateTime)" do
      let(:value) { DateTime.new(2019, 9, 28, 0, 0, 0, Rational(0)) }

      it "serializes with +00:00 offset" do
        expect(serialize).to eq("2019-09-28+00:00")
      end
    end

    context "with positive timezone offset (DateTime)" do
      let(:value) { DateTime.new(2019, 12, 2, 0, 0, 0, Rational(8, 24)) }

      it "serializes with offset" do
        expect(serialize).to eq("2019-12-02+08:00")
      end
    end

    context "with negative timezone offset (DateTime)" do
      let(:value) { DateTime.new(2019, 12, 2, 0, 0, 0, Rational(-5, 24)) }

      it "serializes with offset" do
        expect(serialize).to eq("2019-12-02-05:00")
      end
    end

    context "with plain Date (no timezone)" do
      let(:value) { Date.new(2024, 1, 1) }

      it "serializes without timezone" do
        expect(serialize).to eq("2024-01-01")
      end
    end
  end

  describe "#to_xml" do
    subject(:xml_value) { described_class.new(value).to_xml }

    context "with UTC DateTime" do
      let(:value) { DateTime.new(2019, 9, 28, 0, 0, 0, Rational(0)) }

      it "uses Z notation for UTC" do
        expect(xml_value).to eq("2019-09-28Z")
      end
    end

    context "with positive offset DateTime" do
      let(:value) { DateTime.new(2019, 12, 2, 0, 0, 0, Rational(8, 24)) }

      it "uses offset notation" do
        expect(xml_value).to eq("2019-12-02+08:00")
      end
    end

    context "with negative offset DateTime" do
      let(:value) { DateTime.new(2019, 12, 2, 0, 0, 0, Rational(-5, 24)) }

      it "uses offset notation" do
        expect(xml_value).to eq("2019-12-02-05:00")
      end
    end

    context "with plain Date (no timezone)" do
      let(:value) { Date.new(2024, 1, 1) }

      it "serializes without timezone" do
        expect(xml_value).to eq("2024-01-01")
      end
    end
  end

  describe "#to_json" do
    subject(:json_value) { described_class.new(value).to_json }

    context "with UTC DateTime" do
      let(:value) { DateTime.new(2019, 9, 28, 0, 0, 0, Rational(0)) }

      it "uses +00:00 notation for UTC" do
        expect(json_value).to eq("2019-09-28+00:00")
      end
    end

    context "with positive offset DateTime" do
      let(:value) { DateTime.new(2019, 12, 2, 0, 0, 0, Rational(8, 24)) }

      it "uses offset notation" do
        expect(json_value).to eq("2019-12-02+08:00")
      end
    end

    context "with plain Date (no timezone)" do
      let(:value) { Date.new(2024, 1, 1) }

      it "serializes without timezone" do
        expect(json_value).to eq("2024-01-01")
      end
    end
  end
end
