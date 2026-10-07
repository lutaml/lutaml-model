require "spec_helper"
require_relative "fixtures/person"

RSpec.describe Person do
  let(:attributes) do
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
  end

  let(:model) { described_class.new(attributes) }

  let(:attributes_yaml) do
    {
      "firstName" => "John",
      "lastName" => "Doe",
      "age" => 30,
      "height" => 5.9,
      "birthdate" => "1990-01-01",
      "lastLogin" => "2023-06-08T10:00:00+00:00",
      "wakeupTime" => "07:00:00",
      "active" => true,
    }
  end

  let(:attributes_json) do
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
  end

  let(:xml) do
    <<~XML
      <Person xmlns="http://example.com/person" xmlns:nsp1="http://example.com/nsp1">
        <nsp1:FirstName>John</nsp1:FirstName>
        <nsp1:LastName>Doe</nsp1:LastName>
        <Age>30</Age>
        <Height>5.9</Height>
        <Birthdate>1990-01-01</Birthdate>
        <LastLogin>2023-06-08T10:00:00Z</LastLogin>
        <WakeupTime>07:00:00</WakeupTime>
        <Active>true</Active>
      </Person>
    XML
  end

  it "serializes to XML" do
    expect(model.to_xml).to be_xml_equivalent_to(xml)
  end

  it "deserializes from XML" do
    person = described_class.from_xml(xml)
    expect(person.first_name).to eq("John")
    expect(person.age).to eq(30)
    expect(person.height).to eq(5.9)
    expect(person.birthdate).to eq(Date.parse("1990-01-01"))
    expect(person.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(person.wakeup_time).to eq(Time.parse("07:00:00"))
    expect(person.active).to be true
  end

  it "serializes to JSON" do
    expect(model.to_json).to eq(attributes_json.to_json)
  end

  it "deserializes from JSON" do
    json = attributes_json.to_json
    person = described_class.from_json(json)
    expect(person.first_name).to eq("John")
    expect(person.age).to eq(30)
    expect(person.height).to eq(5.9)
    expect(person.birthdate).to eq(Date.parse("1990-01-01"))
    expect(person.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(person.wakeup_time).to eq(Time.parse("07:00:00"))
    expect(person.active).to be true
  end

  it "deserializes from JSON array" do
    json = [attributes_json.dup, attributes_json.dup].to_json

    persons = described_class.from_json(json)

    expect(persons[0].first_name).to eq("John")
    expect(persons[0].age).to eq(30)
    expect(persons[0].height).to eq(5.9)
    expect(persons[0].birthdate).to eq(Date.parse("1990-01-01"))
    expect(persons[0].last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(persons[0].wakeup_time).to eq(Time.parse("07:00:00"))
    expect(persons[0].active).to be true

    expect(persons[1].first_name).to eq("John")
    expect(persons[1].age).to eq(30)
    expect(persons[1].height).to eq(5.9)
    expect(persons[1].birthdate).to eq(Date.parse("1990-01-01"))
    expect(persons[1].last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(persons[1].wakeup_time).to eq(Time.parse("07:00:00"))
    expect(persons[1].active).to be true
  end

  it "serializes to YAML" do
    expect(model.to_yaml).to eq(attributes_yaml.to_yaml)
  end

  # yeptris 0.6.29.x regressed the time-only scalar anchor: "07:00:00"
  # comes back as a fixed 2025-07-19 00:00 instead of today-07:00
  # (psych answers exactly; verified on the psych path). Re-pended
  # until the yeptris typed-materialize ships the fix — evidence on
  # moxml#336. 873a67bd un-pended these on the premise that the
  # 0.6.28.x behavior held; it did not survive the 0.6.29 cut.
  xit "deserializes from YAML" do # rubocop:disable RSpec/PendingWithoutReason -- yeptris time-only misparse; engine fix pending.
    yaml = attributes_yaml.to_yaml
    person = described_class.from_yaml(yaml)
    expect(person.first_name).to eq("John")
    expect(person.age).to eq(30)
    expect(person.height).to eq(5.9)
    expect(person.birthdate).to eq(Date.parse("1990-01-01"))
    expect(person.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(person.wakeup_time).to eq(Time.parse("07:00:00"))
    expect(person.active).to be true
  end

  # Same yeptris time-only scalar misparse as above.
  xit "deserializes from YAML array" do # rubocop:disable RSpec/PendingWithoutReason -- yeptris time-only misparse; engine fix pending.
    yaml = [attributes_yaml.dup, attributes_yaml.dup].to_yaml

    persons = described_class.from_yaml(yaml)

    expect(persons[0].first_name).to eq("John")
    expect(persons[0].age).to eq(30)
    expect(persons[0].height).to eq(5.9)
    expect(persons[0].birthdate).to eq(Date.parse("1990-01-01"))
    expect(persons[0].last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(persons[0].wakeup_time).to eq(Time.parse("07:00:00"))
    expect(persons[0].active).to be true

    expect(persons[1].first_name).to eq("John")
    expect(persons[1].age).to eq(30)
    expect(persons[1].height).to eq(5.9)
    expect(persons[1].birthdate).to eq(Date.parse("1990-01-01"))
    expect(persons[1].last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
    expect(persons[1].wakeup_time).to eq(Time.parse("07:00:00"))
    expect(persons[1].active).to be true
  end
end
