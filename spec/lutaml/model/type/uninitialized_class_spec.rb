# frozen_string_literal: true

require "spec_helper"

RSpec.describe "UninitializedClass handling in Type::Value" do
  describe "base Type::Value.cast" do
    it "returns UninitializedClass instance unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Value.cast(uninit)
      expect(result).to be(uninit)
    end

    it "returns nil for nil value" do
      result = Lutaml::Model::Type::Value.cast(nil)
      expect(result).to be_nil
    end

    it "returns value unchanged for other values" do
      result = Lutaml::Model::Type::Value.cast("hello")
      expect(result).to eq("hello")
    end
  end

  describe "base Type::Value.serialize" do
    it "returns UninitializedClass instance unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Value.serialize(uninit)
      expect(result).to be(uninit)
    end

    it "returns nil for nil value" do
      result = Lutaml::Model::Type::Value.serialize(nil)
      expect(result).to be_nil
    end
  end

  describe "child types with UninitializedClass" do
    it "Date.cast returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Date.cast(uninit)
      expect(result).to be(uninit)
    end

    it "DateTime.cast returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::DateTime.cast(uninit)
      expect(result).to be(uninit)
    end

    it "Time.cast returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Time.cast(uninit)
      expect(result).to be(uninit)
    end

    it "TimeWithoutDate.cast returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::TimeWithoutDate.cast(uninit)
      expect(result).to be(uninit)
    end

    it "Hash.cast returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Hash.cast(uninit)
      expect(result).to be(uninit)
    end

    it "Symbol.cast returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Symbol.cast(uninit)
      expect(result).to be(uninit)
    end

    it "Symbol.cast handles UninitializedClass in serialize" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Model::Type::Symbol.serialize(uninit)
      expect(result).to be(uninit)
    end
  end

  describe "XmlSpaceType.cast with UninitializedClass" do
    it "returns UninitializedClass unchanged" do
      uninit = Lutaml::Model::UninitializedClass.instance
      result = Lutaml::Xml::W3c::XmlSpaceType.cast(uninit)
      expect(result).to be(uninit)
    end

    it "returns nil for nil value" do
      result = Lutaml::Xml::W3c::XmlSpaceType.cast(nil)
      expect(result).to be_nil
    end

    it "validates non-nil, non-uninit values" do
      expect do
        Lutaml::Xml::W3c::XmlSpaceType.cast("invalid")
      end.to raise_error(ArgumentError, "xml:space must be 'default' or 'preserve'")
    end

    it "accepts 'preserve' value" do
      result = Lutaml::Xml::W3c::XmlSpaceType.cast("preserve")
      expect(result).to eq("preserve")
    end

    it "accepts 'default' value" do
      result = Lutaml::Xml::W3c::XmlSpaceType.cast("default")
      expect(result).to eq("default")
    end
  end
end
