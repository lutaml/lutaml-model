# spec/address_spec.rb
require "spec_helper"
require_relative "fixtures/person"
require_relative "fixtures/address"

RSpec.describe Address do
  let(:persons) do
    [
      { first_name: "Tom", last_name: "Warren", age: 40, height: 5.8, birthdate: "1980-02-15", last_login: "2023-06-10T10:00:00Z", wakeup_time: "07:30:00", active: true },
      { first_name: "Jack", last_name: "Warren", age: 35, height: 5.9, birthdate: "1985-05-20", last_login: "2023-06-11T09:00:00Z", wakeup_time: "06:45:00", active: false },
    ]
  end

  let(:address_attributes) do
    {
      country: "USA",
      post_code: "01001",
      persons: persons.map { |attrs| Person.new(attrs) },
    }
  end

  let(:address) { Address.new(address_attributes) }

  it "serializes to JSON with a collection of persons" do
    expected_json = {
      country: "USA",
      postCode: "01001",
      persons: [
        { firstName: "Tom", lastName: "Warren", age: 40, height: 5.8, birthdate: "1980-02-15", lastLogin: "2023-06-10T10:00:00Z", wakeupTime: "07:30:00", active: true },
        { firstName: "Jack", lastName: "Warren", age: 35, height: 5.9, birthdate: "1985-05-20", lastLogin: "2023-06-11T09:00:00Z", wakeupTime: "06:45:00", active: false },
      ],
    }.to_json

    expect(address.to_json).to eq(expected_json)
  end

  it "deserializes from JSON with a collection of persons" do
    json = {
      country: "USA",
      postCode: "01001",
      persons: [
        { firstName: "Tom", lastName: "Warren", age: 40, height: 5.8, birthdate: "1980-02-15", lastLogin: "2023-06-10T10:00:00Z", wakeupTime: "07:30:00", active: true },
        { firstName: "Jack", lastName: "Warren", age: 35, height: 5.9, birthdate: "1985-05-20", lastLogin: "2023-06-11T09:00:00Z", wakeupTime: "06:45:00", active: false },
      ],
    }.to_json

    address_from_json = Address.from_json(json)
    expect(address_from_json.post_code).to eq("01001")
    expect(address_from_json.persons.length).to eq(2)
    expect(address_from_json.persons.first.first_name).to eq("Tom")
    expect(address_from_json.persons.last.first_name).to eq("Jack")
  end

  it "serializes to XML with a collection of persons" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml.Address {
        xml.Country "USA"
        xml.PostCode "01001"
        xml.Persons {
          xml["p"].Person("xmlns:p" => "http://example.com/person") {
            xml["p"].FirstName "Tom"
            xml["p"].LastName "Warren"
            xml.Age "40"
            xml.Height "5.8"
            xml.Birthdate "1980-02-15"
            xml.LastLogin "2023-06-10T10:00:00Z"
            xml.WakeupTime "07:30:00"
            xml.Active "true"
          }
          xml["p"].Person("xmlns:p" => "http://example.com/person") {
            xml["p"].FirstName "Jack"
            xml["p"].LastName "Warren"
            xml.Age "35"
            xml.Height "5.9"
            xml.Birthdate "1985-05-20"
            xml.LastLogin "2023-06-11T09:00:00Z"
            xml.WakeupTime "06:45:00"
            xml.Active "false"
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
          xml["p"].Person("xmlns:p" => "http://example.com/person") {
            xml["p"].FirstName "Tom"
            xml["p"].LastName "Warren"
            xml.Age "40"
            xml.Height "5.8"
            xml.Birthdate "1980-02-15"
            xml.LastLogin "2023-06-10T10:00:00Z"
            xml.WakeupTime "07:30:00"
            xml.Active "true"
          }
          xml["p"].Person("xmlns:p" => "http://example.com/person") {
            xml["p"].FirstName "Jack"
            xml["p"].LastName "Warren"
            xml.Age "35"
            xml.Height "5.9"
            xml.Birthdate "1985-05-20"
            xml.LastLogin "2023-06-11T09:00:00Z"
            xml.WakeupTime "06:45:00"
            xml.Active "false"
          }
        }
      }
    end.to_xml

    address_from_xml = Address.from_xml(xml)
    expect(address_from_xml.post_code).to eq("01001")
    expect(address_from_xml.persons.length).to eq(2)
    expect(address_from_xml.persons.first.first_name).to eq("Tom")
    expect(address_from_xml.persons.last.first_name).to eq("Jack")
  end
end
