require "spec_helper"
require "lutaml/model"

module ChoiceAndGroup
  class PersonDetails < Lutaml::Model::Serializable
    choice do
      attribute :full_name, :string

      group do
        choice do
          attribute :prefix, :string
          attribute :first_name, :string
          attribute :middle_name, :integer
          attribute :last_name, :string
          attribute :suffix, :float, raw: true
        end
      end
    end

    attribute :nickname, :string
    attribute :preferred_language, :string

    choice do
      attribute :is_active, :boolean, default: -> { true }
    end

    group do
      choice do
        attribute :government_id, :decimal
        group do
          choice do
            attribute :national_id, :string
            attribute :driver_id, :string
          end
        end
      end
    end

    sequence do
      group do
        sequence do
          attribute :name, :string
          attribute :age, :integer
        end
      end

      attribute :gender, :string
    end

    sequence do
      choice do
        attribute :caste, :string
        attribute :degree, :string
      end
    end
  end

  class PersonPreferences < Lutaml::Model::Serializable
    attribute :contact_method, :string

    choice do
      attribute :first_name, :string
      choice do
        attribute :email, :string
        attribute :phone, :string
        choice do
          attribute :fb, :string
          attribute :insta, :string
        end
      end
    end

    choice do
      attribute :middle_name, :string
      attribute :last_name, :string
      attribute :suffix, :string
      choice do
        attribute :introvert, :string
        attribute :extrovert, :string
      end
    end

    attribute :foo, :string
  end
end

RSpec.describe "ChoiceGroup" do
  context "with nested group and choice option" do
    let(:mapper) { ChoiceAndGroup::PersonDetails }

    it "returns an empty array for a valid nested group choice instance" do
      valid_instance = mapper.new(
        prefix: "prefix",
        nickname: "bib",
        preferred_language: "preferred_language",
        is_active: true,
        government_id: 2.3,
        name: "John",
        age: 24,
        gender: "male",
        degree: "BSCS",
      )

      expect(valid_instance.validate).to be_empty
    end

    it "returns an empty array for a valid nested group choice instance with different selections" do
      valid_instance = mapper.new(
        full_name: "jcom",
        nickname: "bib",
        preferred_language: "preferred_language",
        is_active: true,
        national_id: "national_id",
        name: "John",
        age: 24,
        gender: "male",
        caste: "White",
      )

      expect(valid_instance.validate).to be_empty
    end

    it "returns nil for a valid instance, if given attribute for choice is one" do
      valid_instance = mapper.new(
        prefix: "prefix",
        nickname: "bib",
        preferred_language: "preferred_language",
        is_active: true,
        government_id: 2.5,
        name: "John",
        age: 24,
        gender: "male",
        degree: "BSCS",
      )

      expect(valid_instance.validate!).to be_nil
    end

    it "raises error, if more than one attributes given for choice" do
      valid_instance = mapper.new(
        prefix: "jpre",
        first_name: "jfore",
        full_name: "jcom",
        is_active: true,
        government_id: 3.8,
        driver_id: "tao",
        national_id: "fbbi",
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Exactly one attribute must be specified in a choice")
      end
    end

    it "raises error, if none of the choice attributes are given" do
      valid_instance = mapper.new(
        nickname: "jbib",
        preferred_language: "jvar",
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Exactly one attribute must be specified in a choice")
      end
    end
  end

  context "with choice option" do
    let(:mapper) { ChoiceAndGroup::PersonPreferences }

    it "returns an empty array for a valid instance" do
      valid_instance = mapper.new(
        contact_method: "contact_method",
        fb: "fb",
        last_name: "usher",
        foo: "sjoo",
      )

      expect(valid_instance.validate).to be_empty
    end

    it "returns nil for a valid instance, if given attribute for choice is one" do
      valid_instance = mapper.new(
        contact_method: "contact_method",
        email: "email",
        suffix: "suffix",
        foo: "jjoo",
      )

      expect(valid_instance.validate!).to be_nil
    end

    it "raises error, if given attributes are more than one in choice" do
      valid_instance = mapper.new(
        contact_method: "contact_method",
        email: "email",
        phone: "phone",
        middle_name: "middle_name",
        suffix: "suffix",
        foo: "jjoo",
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Exactly one attribute must be specified in a choice")
      end
    end

    it "raises error, if none of the choice attributes given" do
      valid_instance = mapper.new(
        contact_method: "contact_method",
        foo: "foo",
      )

      expect { valid_instance.validate! }.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("Exactly one attribute must be specified in a choice")
      end
    end
  end

  context "with group option" do
    it "raises error when attribute is defined directly in it" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          group do
            attribute :prefix, :string
          end
        end
      end.to raise_error(Lutaml::Model::InvalidGroupError, "Attributes can't be defined directly in group")
    end

    it "raises error when nested group defined" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          group do
            group do
              attribute :last_name, :string
            end
          end
        end
      end.to raise_error(Lutaml::Model::InvalidGroupError, "Nested group definitions are not allowed")
    end

    it "raises error when multiple choices given in it" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          group do
            choice do
              attribute :prefix, :string
              attribute :first_name, :string
            end

            choice do
              attribute :middle_name, :string
              attribute :last_name, :string
              attribute :suffix, :string
            end
          end
        end
      end.to raise_error(Lutaml::Model::InvalidGroupError, "Can't define multiple choices in group")
    end

    it "raises error when group is empty" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          group do
            # empty group testing
          end
        end
      end.to raise_error(Lutaml::Model::InvalidGroupError, "Group can't be empty")
    end
  end
end
