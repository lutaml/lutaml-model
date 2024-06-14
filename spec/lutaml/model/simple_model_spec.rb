# spec/lutaml/model/simple_model_spec.rb
require "spec_helper"
require "lutaml/model"

module SimpleModel
  class Address < Lutaml::Model::Serializable
    attribute :street, Lutaml::Model::Type::String
    attribute :city, Lutaml::Model::Type::String

    xml do
      root "address"
      map_element "street", to: :street
      map_element "city", to: :city
    end

    yaml do
      map "street", to: :street
      map "city", to: :city
    end

    json do
      map "street", to: :street
      map "city", to: :city
    end

    toml do
      map "street", to: :street
      map "city", to: :city
    end
  end

  class Room < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String, default: -> { "Unnamed room" }
    attribute :size, Lutaml::Model::Type::Integer

    xml do
      root "room"
      map_element "name", to: :name
      map_element "size", to: :size
    end

    yaml do
      map "name", to: :name
      map "size", to: :size
    end

    json do
      map "name", to: :name
      map "size", to: :size
    end

    toml do
      map "name", to: :name
      map "size", to: :size
    end
  end

  class Building < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String, default: -> { "Unnamed building" }
    attribute :address, Address
    attribute :rooms, Room, collection: true

    xml do
      root "building"
      map_attribute "name", to: :name
      map_element "address", to: :address
      map_element "room", to: :rooms
    end

    yaml do
      map "name", to: :name
      map "address", to: :address
      map "rooms", to: :rooms
    end

    json do
      map "name", to: :name
      map "address", to: :address
      map "rooms", to: :rooms
    end

    toml do
      map "name", to: :name
      map "address", to: :address
      map "rooms", to: :rooms
    end
  end
end

RSpec.describe SimpleModel do
  let(:address) { SimpleModel::Address.new(street: "123 Main St", city: "Anytown") }
  let(:rooms) { [SimpleModel::Room.new(name: "Conference Room", size: 30), SimpleModel::Room.new(name: "Office", size: 20)] }
  let(:attributes) { { name: "Headquarters", address: address, rooms: rooms } }
  let(:model) { SimpleModel::Building.new(attributes) }

  let(:model_xml) {
    <<~XML
      <building name="Headquarters">
        <address>
          <street>123 Main St</street>
          <city>Anytown</city>
        </address>
        <room>
          <name>Conference Room</name>
          <size>30</size>
        </room>
        <room>
          <name>Office</name>
          <size>20</size>
        </room>
      </building>
    XML
  }

  let(:model_yaml) {
    <<~YAML
      name: Headquarters
      address:
        street: 123 Main St
        city: Anytown
      rooms:
        - name: Conference Room
          size: 30
        - name: Office
          size: 20
    YAML
  }

  let(:model_json) {
    <<~JSON
      {
        "name": "Headquarters",
        "address": {
          "street": "123 Main St",
          "city": "Anytown"
        },
        "rooms": [
          {
            "name": "Conference Room",
            "size": 30
          },
          {
            "name": "Office",
            "size": 20
          }
        ]
      }
    JSON
  }

  let(:model_toml) {
    <<~TOML
      name = "Headquarters"

      [address]
      street = "123 Main St"
      city = "Anytown"

      [[rooms]]
      name = "Conference Room"
      size = 30

      [[rooms]]
      name = "Office"
      size = 20
    TOML
  }

  let(:model_yaml_missing_element) {
    <<~YAML
      name: Headquarters
      rooms:
        - name: Conference Room
          size: 30
        - name: Office
          size: 20
    YAML
  }

  it "initializes with default values" do
    default_model = Building.new
    expect(default_model.name).to eq(nil)
    expect(default_model.address).to eq(nil)
    expect(default_model.rooms).to eq([])
  end

  it "serializes to XML" do
    expected_xml = model_xml.strip
    expect(model.to_xml.strip).to eq(expected_xml)
  end

  it "deserializes from XML" do
    sample = Building.from_xml(model_xml)
    expect(sample.name).to eq("Headquarters")
    expect(sample.address.street).to eq("123 Main St")
    expect(sample.address.city).to eq("Anytown")
    expect(sample.rooms.size).to eq(2)
    expect(sample.rooms[0].name).to eq("Conference Room")
    expect(sample.rooms[0].size).to eq(30)
    expect(sample.rooms[1].name).to eq("Office")
    expect(sample.rooms[1].size).to eq(20)
  end

  it "round-trips XML" do
    xml = model.to_xml
    new_model = Building.from_xml(xml)
    expect(new_model.name).to eq(model.name)
    expect(new_model.address.street).to eq(model.address.street)
    expect(new_model.address.city).to eq(model.address.city)
    expect(new_model.rooms.size).to eq(model.rooms.size)
    model.rooms.each_with_index do |room, index|
      expect(new_model.rooms[index].name).to eq(room.name)
      expect(new_model.rooms[index].size).to eq(room.size)
    end
  end

  it "serializes to YAML" do
    expected_yaml = model_yaml.strip
    expect(model.to_yaml.strip).to eq(expected_yaml)
  end

  it "deserializes from YAML" do
    sample = Building.from_yaml(model_yaml)
    expect(sample.name).to eq("Headquarters")
    expect(sample.address.street).to eq("123 Main St")
    expect(sample.address.city).to eq("Anytown")
    expect(sample.rooms.size).to eq(2)
    expect(sample.rooms[0].name).to eq("Conference Room")
    expect(sample.rooms[0].size).to eq(30)
    expect(sample.rooms[1].name).to eq("Office")
    expect(sample.rooms[1].size).to eq(20)
  end

  it "round-trips YAML" do
    yaml = model.to_yaml
    new_model = Building.from_yaml(yaml)
    expect(new_model.name).to eq(model.name)
    expect(new_model.address.street).to eq(model.address.street)
    expect(new_model.address.city).to eq(model.address.city)
    expect(new_model.rooms.size).to eq(model.rooms.size)
    model.rooms.each_with_index do |room, index|
      expect(new_model.rooms[index].name).to eq(room.name)
      expect(new_model.rooms[index].size).to eq(room.size)
    end
  end

  it "serializes to YAML without the omitted element" do
    model_without_address = Building.new(name: "Headquarters", rooms: rooms)
    expected_yaml = model_yaml_missing_element.strip
    expect(model_without_address.to_yaml.strip).to eq(expected_yaml)
  end

  it "serializes to JSON" do
    expected_json = model_json.strip
    expect(model.to_json.strip).to eq(expected_json)
  end

  it "deserializes from JSON" do
    sample = Building.from_json(model_json)
    expect(sample.name).to eq("Headquarters")
    expect(sample.address.street).to eq("123 Main St")
    expect(sample.address.city).to eq("Anytown")
    expect(sample.rooms.size).to eq(2)
    expect(sample.rooms[0].name).to eq("Conference Room")
    expect(sample.rooms[0].size).to eq(30)
    expect(sample.rooms[1].name).to eq("Office")
    expect(sample.rooms[1].size).to eq(20)
  end

  it "round-trips JSON" do
    json = model.to_json
    new_model = Building.from_json(json)
    expect(new_model.name).to eq(model.name)
    expect(new_model.address.street).to eq(model.address.street)
    expect(new_model.address.city).to eq(model.address.city)
    expect(new_model.rooms.size).to eq(model.rooms.size)
    model.rooms.each_with_index do |room, index|
      expect(new_model.rooms[index].name).to eq(room.name)
      expect(new_model.rooms[index].size).to eq(room.size)
    end
  end

  it "serializes to TOML" do
    expected_toml = model_toml.strip
    expect(model.to_toml.strip).to eq(expected_toml)
  end

  it "deserializes from TOML" do
    sample = Building.from_toml(model_toml)
    expect(sample.name).to eq("Headquarters")
    expect(sample.address.street).to eq("123 Main St")
    expect(sample.address.city).to eq("Anytown")
    expect(sample.rooms.size).to eq(2)
    expect(sample.rooms[0].name).to eq("Conference Room")
    expect(sample.rooms[0].size).to eq(30)
    expect(sample.rooms[1].name).to eq("Office")
    expect(sample.rooms[1].size).to eq(20)
  end

  it "round-trips TOML" do
    toml = model.to_toml
    new_model = Building.from_toml(toml)
    expect(new_model.name).to eq(model.name)
    expect(new_model.address.street).to eq(model.address.street)
    expect(new_model.address.city).to eq(model.address.city)
    expect(new_model.rooms.size).to eq(model.rooms.size)
    model.rooms.each_with_index do |room, index|
      expect(new_model.rooms[index].name).to eq(room.name)
      expect(new_model.rooms[index].size).to eq(room.size)
    end
  end
end
