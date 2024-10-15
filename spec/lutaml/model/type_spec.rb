require "spec_helper"
require_relative "../../../lib/lutaml/model/type"

RSpec.describe Lutaml::Model::Type do
  describe ".to_boolean" do
    context "when value is true" do
      it "returns true" do
        expect(described_class.to_boolean(true)).to be true
      end
    end

    context "when value is false" do
      it "returns false" do
        expect(described_class.to_boolean(false)).to be false
      end
    end

    context "when value is nil" do
      it "returns false" do
        expect(described_class.to_boolean(nil)).to be false
      end
    end

    context "when value is a string" do
      it 'returns true for "true"' do
        expect(described_class.to_boolean("true")).to be true
      end

      it 'returns true for "t"' do
        expect(described_class.to_boolean("t")).to be true
      end

      it 'returns true for "yes"' do
        expect(described_class.to_boolean("yes")).to be true
      end

      it 'returns true for "y"' do
        expect(described_class.to_boolean("y")).to be true
      end

      it 'returns true for "1"' do
        expect(described_class.to_boolean("1")).to be true
      end

      it 'returns false for "false"' do
        expect(described_class.to_boolean("false")).to be false
      end

      it 'returns false for "f"' do
        expect(described_class.to_boolean("f")).to be false
      end

      it 'returns false for "no"' do
        expect(described_class.to_boolean("no")).to be false
      end

      it 'returns false for "n"' do
        expect(described_class.to_boolean("n")).to be false
      end

      it 'returns false for "0"' do
        expect(described_class.to_boolean("0")).to be false
      end

      it "raises ArgumentError for an unrecognized string" do
        expect do
          described_class.to_boolean("unrecognized")
        end.to raise_error(ArgumentError,
                           'invalid value for Boolean: "unrecognized"')
      end
    end

    context "when value is an integer" do
      it "raises ArgumentError" do
        expect do
          described_class.to_boolean(123)
        end.to raise_error(ArgumentError,
                           'invalid value for Boolean: "123"')
      end
    end

    context "when value is an array" do
      it "raises ArgumentError" do
        expect do
          described_class.to_boolean([1, 2,
                                      3])
        end.to raise_error(ArgumentError,
                           'invalid value for Boolean: "[1, 2, 3]"')
      end
    end

    context "when value is a hash" do
      it "raises ArgumentError" do
        hash = { key: "value" }
        expect do
          described_class.to_boolean(hash)
        end.to raise_error(ArgumentError,
                           "invalid value for Boolean: \"#{hash}\"")
      end
    end

    context "when value is an object" do
      it "raises ArgumentError" do
        obj = Object.new
        expect do
          described_class.to_boolean(obj)
        end.to raise_error(ArgumentError,
                           "invalid value for Boolean: \"#{obj}\"")
      end
    end
  end
end
