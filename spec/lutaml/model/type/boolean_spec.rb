require "spec_helper"

module BooleanSpec
  class Employee < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :full_time, :boolean
    attribute :remote, :boolean

    key_value do
      map "name", to: :name
      map "full_time", to: :full_time
      map "remote", to: :remote
    end
  end
end

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

  context "with key-value serialization" do
    let(:yaml) do
      <<~YAML
        ---
        name: John Smith
        full_time: true
        remote: false
      YAML
    end

    it "deserializes boolean values correctly" do
      employee = BooleanSpec::Employee.from_yaml(yaml)

      expect(employee.name).to eq("John Smith")
      expect(employee.full_time).to be true
      expect(employee.remote).to be false
    end

    it "serializes boolean values correctly" do
      employee = BooleanSpec::Employee.new(
        name: "John Smith",
        full_time: true,
        remote: false,
      )

      yaml_output = employee.to_yaml
      expect(yaml_output).to eq(yaml)
    end
  end
end
