require "spec_helper"

RSpec.describe Lutaml::Model::Type::Boolean do
  describe ".cast" do
    let(:truthy_values) { [true, "true", "t", "yes", "y", "1"] }
    let(:falsey_values) { [false, "false", "f", "no", "n", "0"] }

    it "returns nil for nil input" do
      expect(described_class.cast(nil)).to be_nil
    end

    context "with truthy values" do
      it "casts to true" do
        truthy_values.each do |value|
          expect(described_class.cast(value)).to be true
        end
      end
    end

    context "with falsey values" do
      it "casts to false" do
        falsey_values.each do |value|
          expect(described_class.cast(value)).to be false
        end
      end
    end

    context "with other values" do
      it "returns the original value" do
        value = "other"
        expect(described_class.cast(value)).to eq value
      end
    end
  end

  describe ".serialize" do
    it "returns nil for nil input" do
      expect(described_class.serialize(nil)).to be_nil
    end

    it "returns true for truthy input" do
      expect(described_class.serialize(true)).to be true
    end

    it "returns false for falsey input" do
      expect(described_class.serialize(false)).to be false
    end

    it "preserves input boolean values" do
      expect(described_class.serialize(false)).to be false
      expect(described_class.serialize(true)).to be true
    end
  end
end
