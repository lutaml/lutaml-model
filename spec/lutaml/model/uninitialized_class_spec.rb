# frozen_string_literal: true

RSpec.describe Lutaml::Model::UninitializedClass do
  subject(:uninitialized) { described_class.instance }

  describe "#to_s" do
    it "returns self" do
      expect(uninitialized.to_s).to eq(uninitialized)
    end
  end

  describe "#inspect" do
    it "returns 'uninitialized'" do
      expect(uninitialized.inspect).to eq("uninitialized")
    end
  end

  describe "#uninitialized?" do
    it "returns true" do
      expect(uninitialized.uninitialized?).to be true
    end
  end

  describe "#match?" do
    it "returns false for any argument" do
      expect(uninitialized).not_to match /pattern/
      expect(uninitialized).not_to match "string"
      expect(uninitialized).not_to match nil
    end
  end

  describe "#include?" do
    it "returns false for any argument" do
      expect(uninitialized).not_to include "substring"
      expect(uninitialized).not_to include nil
    end
  end

  describe "#gsub" do
    it "returns self regardless of arguments" do
      expect(uninitialized.gsub("pattern", "replacement")).to eq(uninitialized)
      expect(uninitialized.gsub("pattern", "replacement")).to eq(uninitialized)
    end
  end

  describe "#to_yaml" do
    it "returns nil" do
      expect(uninitialized.to_yaml).to be_nil
    end
  end

  describe "#to_f" do
    it "returns self" do
      expect(uninitialized.to_f).to eq(uninitialized)
    end
  end

  describe "#size" do
    it "returns 0" do
      expect(uninitialized.size).to eq(0)
    end
  end

  describe "#encoding" do
    it "returns the default string encoding" do
      expect(uninitialized.encoding).to eq("".encoding)
    end
  end

  describe "method_missing" do
    context "when method ends with '?'" do
      it "returns false" do
        expect(uninitialized).not_to be_empty
        expect(uninitialized).not_to be_nil
        expect(uninitialized).not_to be_blank
      end
    end

    context "when method doesn't end with '?'" do
      it "raises NoMethodError" do
        expect { uninitialized.unknown_method }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#respond_to_missing?" do
    it "returns true for methods ending with ?" do
      expect(uninitialized.respond_to?(:empty?)).to be true
      expect(uninitialized.respond_to?(:nil?)).to be true
    end

    it "returns false for methods not ending with ?" do
      expect(uninitialized.respond_to?(:unknown_method)).to be false
    end
  end
end
