# spec/person_spec.rb
require "spec_helper"
require_relative "fixtures/person"

RSpec.describe Person do
  let(:attributes) {
    {
      first_name: "John",
      last_name: "Doe",
      age: 30,
      height: 5.9,
      birthdate: "1990-01-01",
      last_login: "2023-06-08T10:00:00+00:00",
      wakeup_time: "07:00:00",
      active: true,
    }
  }

  let(:model) { Person.new(attributes) }

  it "serializes to XML" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml["p"].Person("xmlns:p" => "http://example.com/person") {
        xml["p"].FirstName "John"
        xml["p"].LastName "Doe"
        xml.Age "30"
        xml.Height "5.9"
        xml.Birthdate "1990-01-01"
        xml.LastLogin "2023-06-08T10:00:00+00:00"
        xml.WakeupTime "07:00:00"
        xml.Active "true"
      }
    end.to_xml
    expect(Nokogiri::XML(model.to_xml).to_s).to eq(Nokogiri::XML(expected_xml).to_s)
  end

  it "deserializes from XML" do
    xml = Nokogiri::XML::Builder.new do |xml|
      xml["p"].Person("xmlns:p" => "http://example.com/person") {
        xml["p"].FirstName "John"
        xml["p"].LastName "Doe"
        xml.Age "30"
        xml.Height "5.9"
        xml.Birthdate "1990-01-01"
        xml.LastLogin "2023-06-08T10:00:00+00:00"
        xml.WakeupTime "07:00:00"
        xml.Active "true"
      }
    end.to_xml
    person = Person.from_xml(xml)
    expect(person.first_name).to eq("John")
    expect(person.age).to eq(30)
    expect(person.height).to eq(5.9)
    expect(person.birthdate).to eq(Date.parse("1990-01-01"))
    expect(person.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(person.wakeup_time).to eq(Time.parse("07:00:00"))
    expect(person.active).to be true
  end

  let(:attributes_json) {
    {
      firstName: "John",
      lastName: "Doe",
      age: 30,
      height: 5.9,
      birthdate: "1990-01-01",
      lastLogin: "2023-06-08T10:00:00+00:00",
      wakeupTime: "07:00:00",
      active: true,
    }
  }
  it "serializes to JSON" do
    expect(model.to_json).to eq(attributes_json.to_json)
  end

  it "deserializes from JSON" do
    json = attributes.to_json
    person = Person.from_json(json)
    expect(person.first_name).to eq("John")
    expect(person.age).to eq(30)
    expect(person.height).to eq(5.9)
    expect(person.birthdate).to eq(Date.parse("1990-01-01"))
    expect(person.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(person.wakeup_time).to eq(Time.parse("07:00:00"))
    expect(person.active).to be true
  end

  let(:attributes_yaml) {
    {
      "firstName" => "John",
      "lastName" => "Doe",
    }
  }
  it "serializes to YAML" do
    expect(model.to_yaml).to eq(attributes_yaml.to_yaml)
  end

  it "deserializes from YAML" do
    yaml = attributes.to_yaml
    person = Person.from_yaml(yaml)
    expect(person.first_name).to eq("John")
    expect(person.age).to eq(30)
    expect(person.height).to eq(5.9)
    expect(person.birthdate).to eq(Date.parse("1990-01-01"))
    expect(person.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(person.wakeup_time).to eq(Time.parse("07:00:00"))
    expect(person.active).to be true
  end
end
