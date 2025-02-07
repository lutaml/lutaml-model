require "spec_helper"
require "lutaml/model"

module ChoiceSpec
  class CandidateType < Lutaml::Model::Serializable
    attribute :id, :integer
    attribute :name, :string

    xml do
      map_attribute "id", to: :id
      map_attribute "name", to: :name
    end
  end

  class DocumentState < Lutaml::Model::Serializable
    choice(min: 1, max: 3) do
      attribute :signed, :boolean
      attribute :unsigned, :boolean
      attribute :watermarked, :boolean
      attribute :encrypted, :boolean
    end

    attribute :candidate, CandidateType

    xml do
      map_element "signed", to: :signed
      map_element "unsigned", to: :unsigned
      map_element "watermarked", to: :watermarked
      map_element "encrypted", to: :encrypted
      map_attribute "candidate", to: :candidate
    end
  end

  class PersonDetails < Lutaml::Model::Serializable
    choice(min: 1, max: 3) do
      attribute :first_name, :string
      attribute :middle_name, :string
      choice(min: 2, max: 2) do
        attribute :email, :string
        attribute :phone, :string
        attribute :check, :string
      end
    end

    choice(min: 1, max: 2) do
      attribute :fb, :string
      choice(min: 1, max: 1) do
        attribute :insta, :string
        attribute :last_name, :string
      end
    end

    key_value do
      map :first_name, to: :first_name
      map :email, to: :email
      map :phone, to: :phone
      map :fb, to: :fb
      map :insta, to: :insta
      map :last_name, to: :last_name
    end
  end
end

RSpec.describe "Choice" do
  context "with choice option" do
    let(:mapper) { ChoiceSpec::DocumentState }

    it "returns an empty array for a valid choice instance" do
      valid_instance = mapper.new(
        signed: true,
        unsigned: true,
        watermarked: false,
        candidate: ChoiceSpec::CandidateType.new(id: 1, name: "Smith"),
      )

      expect(valid_instance.validate).to be_empty
    end

    it "returns nil for a valid instance, if given attributes for choice are within defined range" do
      valid_instance = mapper.new(
        watermarked: false,
        encrypted: true,
      )

      expect(valid_instance.validate!).to be_nil
    end

    it "raises error, if attributes given for choice are out of upper bound" do
      valid_instance = mapper.new(
        signed: true,
        unsigned: false,
        watermarked: false,
        encrypted: true,
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Attributes `[:signed, :unsigned, :watermarked, :encrypted]` count exceeds the upper bound `3`")
      end
    end
  end

  context "with nested choice option" do
    let(:mapper) { ChoiceSpec::PersonDetails }

    it "returns an empty array for a valid instance" do
      valid_instance = mapper.new(
        first_name: "John",
        middle_name: "S",
        fb: "fb",
      )

      expect(valid_instance.validate).to be_empty
    end

    it "returns nil for a valid instance" do
      valid_instance = mapper.new(
        email: "email",
        phone: "02344",
        last_name: "last_name",
      )

      expect(valid_instance.validate!).to be_nil
    end

    it "raises error, if given attribute for choice are not within upper bound" do
      valid_instance = mapper.new(
        first_name: "Nick",
        email: "email",
        phone: "phone",
        check: "check",
        fb: "fb",
        insta: "insta",
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to eq("Attributes `[:email, :phone, :check]` count exceeds the upper bound `2`")
      end
    end

    it "raises error, if given attribute for choice are not within lower bound" do
      valid_instance = mapper.new(
        fb: "fb",
        insta: "insta",
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to eq("Attributes `[]` count is less than the lower bound `1`")
      end
    end

    it "raises error, if min, max is not positive" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          choice(min: -1, max: -2) do
            attribute :id, :integer
            attribute :name, :string
          end
        end
      end.to raise_error(Lutaml::Model::InvalidChoiceRangeError, "Choice lower bound `-1` must be positive")
    end
  end
end
