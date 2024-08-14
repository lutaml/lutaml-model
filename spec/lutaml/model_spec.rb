# frozen_string_literal: true

class TestClassEnum < Lutaml::Model::Serializable
  attribute :name, Lutaml::Model::Type::String
  attribute :age, Lutaml::Model::Type::Integer
end

class WithClassEnum < Lutaml::Model::Serializable
  attribute :first,
            TestClassEnum,
            values: [
              TestClassEnum.new({ name: "Alan", age: 16 }),
              TestClassEnum.new({ name: "Bobby", age: 16 }),
              TestClassEnum.new({ name: "Bobby", age: 18 }),
            ]
end

class WithStringEnum < Lutaml::Model::Serializable
  attribute :first, Lutaml::Model::Type::String, values: ["one", "two", "three"]
end

RSpec.describe Lutaml::Model do
  context "when enum is string type" do
    context "when value is not allowed" do
      it "raises error when assigning after creation" do
        object = WithStringEnum.new(first: "one")

        expect do
          object.first = "four"
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end

      it "raises error when assigning when creation" do
        expect do
          WithStringEnum.new(first: "five")
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end
    end

    context "when value is allowed" do
      it "changes value when assigning after creation" do
        object = WithStringEnum.new(first: "one")

        expect { object.first = "two" }.to change { object.first }
          .from("one")
          .to("two")
      end

      it "assign value when creating" do
        object = WithStringEnum.new(first: "three")

        expect(object.first).to eq("three")
      end
    end
  end

  # Tests using Lutaml::Model objects comparison.
  context "when enum is class type" do
    context "when value is not allowed" do
      it "raises error when assigning after creation" do
        object = WithClassEnum.new(first: TestClassEnum.new(name: "Alan",
                                                            age: 16))

        # TODO: This fails as we need to make a "#validate" method to check
        # the Model which calls "#validate" on all its attributes.
        expect do
          object.first.age = 18
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end

      it "raises error when assigning when creation" do
        expect do
          WithClassEnum.new(first: TestClassEnum.new(name: "Alan", age: 22))
        end.to raise_error(Lutaml::Model::InvalidValueError)
      end
    end

    context "when value is allowed" do
      it "changes value when assigning after creation" do
        object = WithClassEnum.new(first: TestClassEnum.new(name: "Alan",
                                                            age: 16))

        expect { object.first.name = "Bobby" }.to change { object.first.name }
          .from("Alan")
          .to("Bobby")
      end

      it "assign value when creating" do
        object = WithClassEnum.new(first: TestClassEnum.new(name: "Alan",
                                                            age: 16))

        expect(object.first.name).to eq("Alan")
      end
    end
  end
end
