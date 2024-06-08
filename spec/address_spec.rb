# spec/address_spec.rb
require "spec_helper"
require_relative "fixtures/address"
require_relative "fixtures/person"

RSpec.describe Address do
  let(:person1) {
    {
      first_name: "Tom",
      last_name: "Warren",
      age: 40,
      height: 5.8,
      birthdate: Date.new(1980, 2, 15),
      last_login: "1980-02-15T10:00:00Z",
      wakeup_time: "07:30:00",
      active: true,
    }
  }
  let(:person2) {
    {
      first_name: "Jack",
      last_name: "Warren",
      age: 35,
      height: 5.9,
      birthdate: Date.new(1985, 5, 20),
      last_login: "1985-05-20T09:00:00Z",
      wakeup_time: "06:45:00",
      active: false,
    }
  }
  let(:attributes) {
    {
      country: "USA",
      post_code: "01001",
      persons: [Person.new(person1), Person.new(person2)],
    }
  }
  let(:address) { Address.new(attributes) }

  it "serializes to JSON with a collection of persons" do
    expected_json = {
      country: "USA",
      postCode: "01001",
      persons: [
        {
          firstName: "Tom",
          lastName: "Warren",
          age: 40,
          height: 5.8,
          birthdate: "1980-02-15",
          lastLogin: "1980-02-15T10:00:00Z",
          wakeupTime: "07:30:00",
          active: true,
        },
        {
          firstName: "Jack",
          lastName: "Warren",
          age: 35,
          height: 5.9,
          birthdate: "1985-05-20",
          lastLogin: "1985-05-20T09:00:00Z",
          wakeupTime: "06:45:00",
          active: false,
        },
      ],
    }.to_json

    expect(address.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with a collection of persons" do
    json = {
      country: "USA",
      postCode: "01001",
      persons: [
        {
          firstName: "Tom",
          lastName: "Warren",
          age: 40,
          height: 5.8,
          birthdate: "1980-02-15",
          lastLogin: "1980-02-15T10:00:00Z",
          wakeupTime: "07:30:00",
          active: true,
        },
        {
          firstName: "Jack",
          lastName: "Warren",
          age: 35,
          height: 5.9,
          birthdate: "1985-05-20",
          lastLogin: "1985-05-20T09:00:00Z",
          wakeupTime: "06:45:00",
          active: false,
        },
      ],
    }.to_json

    address_from_json = Address.from_json(json)
    expect(address_from_json.country).to eq("USA")
    expect(address_from_json.post_code).to eq("01001")
    expect(address_from_json.persons.first.first_name).to eq("Tom")
    expect(address_from_json.persons.last.first_name).to eq("Jack")
  end

  it "serializes to XML with a collection of persons" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml.Address {
        xml.Country "USA"
        xml.PostCode "01001"
        xml.Persons {
          xml.Person {
            xml.FirstName "Tom"
            xml.LastName "Warren"
            xml.Age 40
            xml.Height 5.8
            xml.Birthdate "1980-02-15"
            xml.LastLogin "1980-02-15T10:00:00Z"
            xml.WakeupTime "07:30:00"
            xml.Active true
          }
          xml.Person {
            xml.FirstName "Jack"
            xml.LastName "Warren"
            xml.Age 35
            xml.Height 5.9
            xml.Birthdate "1985-05-20"
            xml.LastLogin "1985-05-20T09:00:00Z"
            xml.WakeupTime "06:45:00"
            xml.Active false
          }
        }
      }
    end.to_xml

    expect(Nokogiri::XML(address.to_xml).to_s).to eq(Nokogiri::XML(expected_xml).to_s)
  end

  it "deserializes from XML with a collection of persons" do
    xml = Nokogiri::XML::Builder.new do |xml|
      xml.Address {
        xml.Country "USA"
        xml.PostCode "01001"
        xml.Persons {
          xml.Person {
            xml.FirstName "Tom"
            xml.LastName "Warren"
            xml.Age 40
            xml.Height 5.8
            xml.Birthdate "1980-02-15"
            xml.LastLogin "1980-02-15T10:00:00Z"
            xml.WakeupTime "07:30:00"
            xml.Active true
          }
          xml.Person {
            xml.FirstName "Jack"
            xml.LastName "Warren"
            xml.Age 35
            xml.Height 5.9
            xml.Birthdate "1985-05-20"
            xml.LastLogin "1985-05-20T09:00:00Z"
            xml.WakeupTime "06:45:00"
            xml.Active false
          }
        }
      }
    end.to_xml

    address_from_xml = Address.from_xml(xml)
    expect(address_from_xml.country).to eq("USA")
    expect(address_from_xml.post_code).to eq("01001")
    expect(address_from_xml.persons.first.first_name).to eq("Tom")
    expect(address_from_xml.persons.last.first_name).to eq("Jack")
  end
end
