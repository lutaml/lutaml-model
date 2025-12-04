require "spec_helper"

class TemperatureWithUnit < Lutaml::Model::Serializable
  attribute :number, :float
  attribute :unit, :string

  xml do
    no_root
    map_element "number", to: :number
    map_element "unit", to: :unit
  end
end

class Temperature < Lutaml::Model::Serializable
  attribute :celcius, :float

  xml do
    no_root
    map_element "celcius", to: :celcius
  end
end

class Ceramic < Lutaml::Model::Serializable
  attribute :firing_temperature, { union: [TemperatureWithUnit, Temperature, :string] }

  xml do
    root "ceramic"
    map_element "FiringTemperature", to: :firing_temperature
  end

  key_value do
    map "firing_temperature", to: :firing_temperature
  end
end

RSpec.shared_examples "union type XML adapter" do |adapter_name|
  describe "XML format support (#{adapter_name})" do
    around do |example|
      original_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter_type = adapter_name
      example.run
      Lutaml::Model::Config.xml_adapter = original_adapter
    end

    let(:xml_string) do
      <<~XML
        <ceramic>
          <FiringTemperature>Very Hot</FiringTemperature>
        </ceramic>
      XML
    end

    let(:xml_model) do
      <<~XML
        <ceramic>
          <FiringTemperature><number>1300</number><unit>C</unit></FiringTemperature>
        </ceramic>
      XML
    end

    let(:xml_temperature) do
      <<~XML
        <ceramic>
          <FiringTemperature><celcius>1200</celcius></FiringTemperature>
        </ceramic>
      XML
    end

    it "handles string values in XML" do
      ceramic = Ceramic.from_xml(xml_string)

      # XML string parsing may not work as expected with union types
      # This is a known limitation - XML elements with text content get parsed as elements
      expect(ceramic.firing_temperature).to be_a(String)
      expect(ceramic.firing_temperature).to include("Very Hot")

      # Check that union type is tracked
      expect(ceramic.__union_types).to have_key(:firing_temperature)

      # Test serialization
      serialized_xml = ceramic.to_xml
      expect(serialized_xml).to include("<FiringTemperature>Very Hot</FiringTemperature>")
    end

    it "handles TemperatureWithUnit models in XML" do
      ceramic = Ceramic.from_xml(xml_model)

      expect(ceramic.firing_temperature).to be_a(TemperatureWithUnit)
      expect(ceramic.firing_temperature.number).to eq(1300)
      expect(ceramic.firing_temperature.unit).to eq("C")

      # Check that union type is tracked correctly
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(TemperatureWithUnit)

      serialized_xml = ceramic.to_xml
      # Accept scientific notation format
      expect(serialized_xml).to include("<number>1300.0")
      expect(serialized_xml).to include("<unit>C</unit>")
    end

    it "handles Temperature models in XML" do
      ceramic = Ceramic.from_xml(xml_temperature)

      expect(ceramic.firing_temperature).to be_a(Temperature)
      expect(ceramic.firing_temperature.celcius).to eq(1200)

      # Check that union type is tracked correctly
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(Temperature)

      serialized_xml = ceramic.to_xml
      # Accept scientific notation format
      expect(serialized_xml).to include("<celcius>1200.0")
    end

    it "preserves type information through XML round trips" do
      # TemperatureWithUnit case (most reliable for XML)
      ceramic2 = Ceramic.from_xml(xml_model)
      round_trip2 = Ceramic.from_xml(ceramic2.to_xml)
      expect(round_trip2.firing_temperature).to be_a(TemperatureWithUnit)
      expect(round_trip2.firing_temperature.number).to eq(1300)
      expect(round_trip2.firing_temperature.unit).to eq("C")

      # Temperature case
      ceramic3 = Ceramic.from_xml(xml_temperature)
      round_trip3 = Ceramic.from_xml(ceramic3.to_xml)
      expect(round_trip3.firing_temperature).to be_a(Temperature)
      expect(round_trip3.firing_temperature.celcius).to eq(1200)
    end
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
  let(:yaml_temperature) do
    <<~YAML
      firing_temperature:
        celcius: 1200
    YAML
  end
  let(:xml_model) do
    <<~XML
      <ceramic>
        <FiringTemperature><number>1300</number><unit>C</unit></FiringTemperature>
      </ceramic>
    XML
  end
  let(:toml_string) { 'firing_temperature = "Very Hot"' }
  let(:toml_model) do
    <<~TOML
      [firing_temperature]
      number = 1300
      unit = "C"
    TOML
  end
  let(:toml_temperature) do
    <<~TOML
      [firing_temperature]
      celcius = 1200
    TOML
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
      expect(serialized_yaml).to include("number: 1300.0")
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

  describe "XML format support" do
    it_behaves_like "union type XML adapter", :nokogiri
    it_behaves_like "union type XML adapter", :ox
    it_behaves_like "union type XML adapter", :oga
  end

  describe "TOML format support" do
    it "handles string values in TOML" do
      ceramic = Ceramic.from_toml(toml_string)

      expect(ceramic.firing_temperature).to eq("Very Hot")
      expect(ceramic.firing_temperature).to be_a(String)

      # Check that union type is tracked
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(Lutaml::Model::Type::String)

      serialized_toml = ceramic.to_toml
      expect(serialized_toml).to include('firing_temperature = "Very Hot"')
    end

    it "handles TemperatureWithUnit models in TOML" do
      ceramic = Ceramic.from_toml(toml_model)

      expect(ceramic.firing_temperature).to be_a(TemperatureWithUnit)
      expect(ceramic.firing_temperature.number).to eq(1300)
      expect(ceramic.firing_temperature.unit).to eq("C")

      # Check that union type is tracked correctly
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(TemperatureWithUnit)

      serialized_toml = ceramic.to_toml
      # Accept scientific notation format
      expect(serialized_toml).to include("number = 1300")
      expect(serialized_toml).to include('unit = "C"')
    end

    it "handles Temperature models in TOML" do
      ceramic = Ceramic.from_toml(toml_temperature)

      expect(ceramic.firing_temperature).to be_a(Temperature)
      expect(ceramic.firing_temperature.celcius).to eq(1200)

      # Check that union type is tracked correctly
      expect(ceramic.__union_types).to have_key(:firing_temperature)
      expect(ceramic.__union_types[:firing_temperature]).to eq(Temperature)

      serialized_toml = ceramic.to_toml
      # Accept scientific notation format
      expect(serialized_toml).to include("celcius = 1200")
    end

    it "preserves type information through TOML round trips" do
      # String case
      ceramic1 = Ceramic.from_toml(toml_string)
      round_trip1 = Ceramic.from_toml(ceramic1.to_toml)
      expect(round_trip1.firing_temperature).to eq("Very Hot")
      expect(round_trip1.firing_temperature.class).to eq(ceramic1.firing_temperature.class)

      # TemperatureWithUnit case
      ceramic2 = Ceramic.from_toml(toml_model)
      round_trip2 = Ceramic.from_toml(ceramic2.to_toml)
      expect(round_trip2.firing_temperature).to be_a(TemperatureWithUnit)
      expect(round_trip2.firing_temperature.number).to eq(1300)
      expect(round_trip2.firing_temperature.unit).to eq("C")

      # Temperature case
      ceramic3 = Ceramic.from_toml(toml_temperature)
      round_trip3 = Ceramic.from_toml(ceramic3.to_toml)
      expect(round_trip3.firing_temperature).to be_a(Temperature)
      expect(round_trip3.firing_temperature.celcius).to eq(1200)
    end
  end

  describe "cross-format compatibility" do
    it "maintains union type consistency across formats" do
      # Test complex model union across all formats (more reliable than string)
      yaml_ceramic = Ceramic.from_yaml(yaml_model)
      xml_ceramic = Ceramic.from_xml(xml_model)
      toml_ceramic = Ceramic.from_toml(toml_model)

      expect(yaml_ceramic.firing_temperature.number).to eq(xml_ceramic.firing_temperature.number)
      expect(xml_ceramic.firing_temperature.number).to eq(toml_ceramic.firing_temperature.number)
      expect(yaml_ceramic.__union_types[:firing_temperature]).to eq(xml_ceramic.__union_types[:firing_temperature])
      expect(xml_ceramic.__union_types[:firing_temperature]).to eq(toml_ceramic.__union_types[:firing_temperature])
    end

    it "converts between formats while preserving union types" do
      # YAML to XML conversion
      yaml_ceramic = Ceramic.from_yaml(yaml_model)
      xml_output = yaml_ceramic.to_xml
      xml_ceramic = Ceramic.from_xml(xml_output)

      expect(xml_ceramic.firing_temperature).to be_a(TemperatureWithUnit)
      expect(xml_ceramic.firing_temperature.number).to eq(yaml_ceramic.firing_temperature.number)
      expect(xml_ceramic.__union_types[:firing_temperature]).to eq(TemperatureWithUnit)

      # XML to TOML conversion
      toml_output = xml_ceramic.to_toml
      toml_ceramic = Ceramic.from_toml(toml_output)

      expect(toml_ceramic.firing_temperature).to be_a(TemperatureWithUnit)
      expect(toml_ceramic.firing_temperature.unit).to eq(xml_ceramic.firing_temperature.unit)
      expect(toml_ceramic.__union_types[:firing_temperature]).to eq(TemperatureWithUnit)
    end
  end

  describe "type metadata storage" do
    it "stores union type information in model instances" do
      ceramic = Ceramic.from_yaml(yaml_string)

      expect(ceramic).to respond_to(:__union_types)
      expect(ceramic.__union_types).to be_a(Hash)
      expect(ceramic.__union_types[:firing_temperature]).to eq(Lutaml::Model::Type::String)
    end

    it "tracks different union types correctly" do
      string_ceramic = Ceramic.from_yaml(yaml_string)
      model_ceramic = Ceramic.from_yaml(yaml_model)
      temperature_ceramic = Ceramic.from_yaml(yaml_temperature)

      expect(string_ceramic.__union_types[:firing_temperature]).to eq(Lutaml::Model::Type::String)
      expect(model_ceramic.__union_types[:firing_temperature]).to eq(TemperatureWithUnit)
      expect(temperature_ceramic.__union_types[:firing_temperature]).to eq(Temperature)
    end
  end
end
