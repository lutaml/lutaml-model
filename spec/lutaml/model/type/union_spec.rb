require "spec_helper"

class TemperatureWithUnit < Lutaml::Model::Serializable
  attribute :number, :decimal
  attribute :unit, :string

  xml do
    no_root
    map_element "number", to: :number
    map_element "unit", to: :unit
  end
end

class Ceramic < Lutaml::Model::Serializable
  attribute :firing_temperature, { union: [TemperatureWithUnit, :string] }

  xml do
    root "ceramic"
    map_element "FiringTemperature", to: :firing_temperature
  end

  key_value do
    map "firing_temperature", to: :firing_temperature
  end
end

RSpec.describe Lutaml::Model::Type::Union do
  let(:yaml_string) { "firing_temperature: Very Hot" }
  let(:yaml_model) do
    <<~YAML
      firing_temperature:
        number: 1300
        unit: C
    YAML
  end

  describe "union types with simple types and complex models" do
    it "handles string values correctly" do
      ceramic = Ceramic.from_yaml(yaml_string)

      expect(ceramic.firing_temperature).to eq("Very Hot")
      expect(ceramic.firing_temperature).to be_a(String)

      # Check that union type is tracked
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(Lutaml::Model::Type::String)

      serialized_yaml = ceramic.to_yaml
      expect(serialized_yaml.strip).to eq("---\nfiring_temperature: Very Hot")
    end

    it "handles complex model values correctly" do
      ceramic = Ceramic.from_yaml(yaml_model)

      expect(ceramic.firing_temperature).to be_a(TemperatureWithUnit)
      expect(ceramic.firing_temperature.number).to eq(1300)
      expect(ceramic.firing_temperature.unit).to eq("C")

      # Check that union type is tracked correctly
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(TemperatureWithUnit)

      serialized_yaml = ceramic.to_yaml
      expect(serialized_yaml).to include("number:")
      expect(serialized_yaml).to include("unit: C")
    end

    it "preserves type information through serialization round trips" do
      # String case
      ceramic1 = Ceramic.from_yaml(yaml_string)
      round_trip1 = Ceramic.from_yaml(ceramic1.to_yaml)
      expect(round_trip1.firing_temperature).to eq("Very Hot")
      expect(round_trip1.firing_temperature.class).to eq(ceramic1.firing_temperature.class)

      # Complex model case
      ceramic2 = Ceramic.from_yaml(yaml_model)
      round_trip2 = Ceramic.from_yaml(ceramic2.to_yaml)
      expect(round_trip2.firing_temperature).to be_a(TemperatureWithUnit)
      expect(round_trip2.firing_temperature.number).to eq(1300)
    end
  end

  describe "type metadata storage" do
    it "stores union type information in model instances" do
      ceramic = Ceramic.from_yaml(yaml_string)

      expect(ceramic).to respond_to(:__union_types)
      expect(ceramic.__union_types).to be_a(Hash)
      expect(ceramic.__union_types[:firing_temperature]).to eq(Lutaml::Model::Type::String)
    end
  end
end
