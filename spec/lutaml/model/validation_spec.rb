# spec/lutaml/model/validation_spec.rb

require "spec_helper"

RSpec.describe Lutaml::Model::Validation do
  before do
    stub_const("ValidationTestClass", Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :age, :integer
      attribute :email, :string,
                values: ["test@example.com", "user@example.com"]
      attribute :tags, :string, collection: true
      attribute :role, :string, collection: 1..3
    end)

    stub_const("ValidationTestMainClass", Class.new(Lutaml::Model::Serializable) do
      attribute :test_class, ValidationTestClass

      xml do
        map_element "test_class", to: :test_class
      end

      key_value do
        map "test_class", to: :test_class
      end
    end)
  end

  let(:valid_instance) do
    ValidationTestClass.new(
      name: "John Doe",
      age: 30,
      email: "test@example.com",
      tags: ["tag1", "tag2"],
      role: ["admin"],
    )
  end

  let(:valid_nested_instance) do
    ValidationTestMainClass.new(
      test_class: valid_instance,
    )
  end

  describe "#validate" do
    it "returns an empty array for a valid instance" do
      expect(valid_instance.validate).to be_empty
    end

    it "returns errors for invalid integer value" do
      instance = ValidationTestClass.new(age: "thirty", role: ["admin"])
      errors = instance.validate
      expect(errors).to eq([])
      expect(instance.age).to be_nil
    end

    it "raises error if Array is set but collection is not set" do
      instance = ValidationTestClass.new(name: ["admin"])
      expect do
        instance.validate
      end.not_to raise_error(Lutaml::Model::CollectionTrueMissingError)
    end

    it "returns errors for value not in allowed set" do
      instance = ValidationTestClass.new(email: "invalid@example.com",
                                         role: ["admin"])
      expect do
        instance.validate!
      end.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("email is `invalid@example.com`, must be one of the following [test@example.com, user@example.com]")
      end
    end

    it "returns errors for invalid collection count" do
      instance = ValidationTestClass.new(role: ["admin", "user", "manager",
                                                "guest"])
      expect do
        instance.validate!
      end.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("role count is 4, must be between 1 and 3")
      end
    end

    it "returns multiple errors for multiple invalid attributes" do
      instance = ValidationTestClass.new(name: "123", age: "thirty",
                                         email: "invalid@example.com", role: [])
      expect do
        instance.validate!
      end.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("email is `invalid@example.com`, must be one of the following [test@example.com, user@example.com]")
        expect(error.error_messages.join("\n")).to include("role count is 0, must be between 1 and 3")
      end
    end

    it "returns an empty array for a valid nested instance" do
      expect(valid_nested_instance.validate).to be_empty
    end
  end

  describe "#validate!" do
    it "does not raise an error for a valid instance" do
      expect { valid_instance.validate! }.not_to raise_error
    end

    it "raises a ValidationError with all error messages for an invalid instance" do
      instance = ValidationTestClass.new(name: "test", age: "thirty")
      expect do
        instance.validate!
      end.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include("role count is 0, must be between 1 and 3")
      end
    end

    it "validates nested ValidationTestClass instance" do
      invalid_nested = ValidationTestMainClass.new(
        test_class: ValidationTestClass.new(
          name: "John Doe",
          age: 30,
          email: "invalid@example.com",
          role: ["admin"],
        ),
      )

      expect do
        invalid_nested.validate!
      end.to raise_error(Lutaml::Model::ValidationError) do |error|
        expect(error.error_messages.join("\n")).to include(
          "email is `invalid@example.com`, must be one of the following [test@example.com, user@example.com]",
        )
      end
    end
  end
end
