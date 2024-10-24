require "spec_helper"
require "lutaml/model"

module GroupAttribute
  class FullNameType < Lutaml::Model::Serializable
    attribute :foo, :string

    group do
      attribute :prefix, :string
      attribute :forename, :string
    end

    group do
      attribute :formatted, :string
      attribute :surname, :string
      attribute :addition, :string
    end

    attribute :joo, :string
  end
end

RSpec.describe GroupAttribute do
  let(:mapper) { GroupAttribute::FullNameType }

  context "with group validation" do
    it "returns an empty array for a valid instance" do
      valid_instance = mapper.new(
        foo: "jbar",
        joo: "joo",
        prefix: "jprefix",
        forename: "jforename",
        formatted: "jformatted",
        surname: "jsurname",
        addition: "jaddition",
      )
      expect(valid_instance.validate).to be_empty
    end

    it "returns nil for a valid instance, all groups attributes selected" do
      valid_instance = mapper.new(
        foo: "jbar",
        joo: "joo",
        prefix: "jprefix",
        forename: "jforename",
        formatted: "jformatted",
        surname: "jsurname",
        addition: "jaddition",
      )
      expect(valid_instance.validate!).to be_nil
    end

    it "returns nil, if one group all attributes not selected" do
      invalid_instance = mapper.new(
        formatted: "jformatted",
        surname: "jsurname",
        addition: "jaddition",
      )
      expect(invalid_instance.validate!).to be_nil
    end

    it "returns error, if a group all attributes not selected" do
      invalid_instance = mapper.new(
        foo: "jbar",
        joo: "joo",
        forename: "jforename",
        formatted: "jformatted",
        surname: "jsurname",
        addition: "jaddition",
      )
      expect { invalid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("prefix is missing or nil, check his group")
      end
    end

    it "return errors, if a group all attributes not selected" do
      invalid_instance = mapper.new(
        foo: "jbar",
        joo: "joo",
        addition: "jaddition",
      )
      expect { invalid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("formatted, surname is missing or nil, check his group")
      end
    end
  end
end
