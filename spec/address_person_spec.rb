require "spec_helper"

module AddressPersonSpec
  class PersonNamespace < Lutaml::Model::XmlNamespace
    uri "http://example.com/person"
    prefix_default "p"
  end

  class Nsp1Namespace < Lutaml::Model::XmlNamespace
    uri "http://example.com/nsp1"
    prefix_default "nsp1"
  end

  class Nsp1String < Lutaml::Model::Type::String
    xml_namespace Nsp1Namespace
  end

  class Person < Lutaml::Model::Serializable
    attribute :first_name, Nsp1String
    attribute :last_name, Nsp1String
    attribute :age, :integer
    attribute :height, :float
    attribute :birthdate, :date
    attribute :last_login, :date_time
    attribute :wakeup_time, :time_without_date
    attribute :active, :boolean

    xml do
      element "Person"
      namespace PersonNamespace

      map_element "FirstName",
                  to: :first_name,
                  render_empty: :omit
      map_element "LastName",
                  to: :last_name,
                  render_empty: :as_blank
      map_element "Age", to: :age
      map_element "Height", to: :height
      map_element "Birthdate", to: :birthdate
      map_element "LastLogin", to: :last_login
      map_element "WakeupTime", to: :wakeup_time
      map_element "Active", to: :active
    end

    json do
      map "firstName", to: :first_name, render_empty: :omit
      map "lastName", to: :last_name, render_empty: :as_empty
      map "age", to: :age, render_empty: :as_nil
      map "height", to: :height
      map "birthdate", to: :birthdate
      map "lastLogin", to: :last_login
      map "wakeupTime", to: :wakeup_time
      map "active", to: :active
    end

    yaml do
      map "firstName", to: :first_name
      map "lastName", with: { to: :yaml_from_last_name, from: :yaml_to_last_name }
      map "age", to: :age
      map "height", to: :height
      map "birthdate", to: :birthdate
      map "lastLogin", to: :last_login
      map "wakeupTime", to: :wakeup_time
      map "active", to: :active
    end

    toml do
      map "first_name", to: :first_name
      map "last_name", to: :last_name
      map "age", to: :age
      map "height", to: :height
      map "birthdate", to: :birthdate
      map "last_login", to: :last_login
      map "wakeup_time", to: :wakeup_time
      map "active", to: :active
    end

    def yaml_from_last_name(model, doc)
      # doc is now a KeyValueElement - use add_child to add custom elements
      doc.add_child(Lutaml::Model::KeyValueDataModel::KeyValueElement.new("lastName", model.last_name))
    end

    def yaml_to_last_name(model, value)
      model.last_name = value
    end
  end

  class Address < Lutaml::Model::Serializable
    attribute :country, :string
    attribute :post_code, :string
    attribute :person, Person, collection: true

    key_value do
      map "country", to: :country
      map "postCode", to: :post_code
      map "person", to: :person
    end

    xml do
      # Address HAS NO NAMESPACE, i.e. BLANK namespace
      element "Address"
      map_element "Country", to: :country
      map_element "PostCode", to: :post_code
      map_element "Person", to: :person
    end
  end

end

RSpec.describe AddressPersonSpec do
  describe AddressPersonSpec::Address do
    let(:tom_warren) do
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
    end
    let(:jack_warren) do
      {
        first_name: "Jack",
        last_name: "Warren",
        age: 35,
        height: 5.9,
        birthdate: Date.new(1985, 5, 20),
        last_login: "1985-05-20T09:00:00+00:00",
        wakeup_time: "06:45:00",
        active: false,
      }
    end
    let(:attributes) do
      {
        country: "USA",
        post_code: "01001",
        person: [tom_warren, jack_warren],
      }
    end
    let(:address) { described_class.new(attributes) }

    it "serializes to JSON with a collection of persons" do
      expected_json = {
        country: "USA",
        postCode: "01001",
        person: [
          {
            firstName: "Tom",
            lastName: "Warren",
            age: 40,
            height: 5.8,
            birthdate: "1980-02-15",
            lastLogin: "1980-02-15T10:00:00+00:00",
            wakeupTime: "07:30:00",
            active: true,
          },
          {
            firstName: "Jack",
            lastName: "Warren",
            age: 35,
            height: 5.9,
            birthdate: "1985-05-20",
            lastLogin: "1985-05-20T09:00:00+00:00",
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
        person: [
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
            lastLogin: "1985-05-20T09:00:00+00:00",
            wakeupTime: "06:45:00",
            active: false,
          },
        ],
      }.to_json

      address_from_json = described_class.from_json(json)
      expect(address_from_json.country).to eq("USA")
      expect(address_from_json.post_code).to eq("01001")
      expect(address_from_json.person.first.first_name).to eq("Tom")
      expect(address_from_json.person.last.first_name).to eq("Jack")
      expect(address_from_json.person.last.active).to be(false)
    end

    it "serializes to XML with a collection of persons" do
      expected_xml = <<~XML
        <Address>
          <Country>USA</Country>
          <PostCode>01001</PostCode>
          <Person xmlns="http://example.com/person" xmlns:nsp1="http://example.com/nsp1">
            <nsp1:FirstName>Tom</nsp1:FirstName>
            <nsp1:LastName>Warren</nsp1:LastName>
            <Age xmlns="">40</Age>
            <Height xmlns="">5.8</Height>
            <Birthdate xmlns="">1980-02-15</Birthdate>
            <LastLogin xmlns="">1980-02-15T10:00:00+00:00</LastLogin>
            <WakeupTime xmlns="">07:30:00</WakeupTime>
            <Active xmlns="">true</Active>
          </Person>
          <Person xmlns="http://example.com/person" xmlns:nsp1="http://example.com/nsp1">
            <nsp1:FirstName>Jack</nsp1:FirstName>
            <nsp1:LastName>Warren</nsp1:LastName>
            <Age xmlns="">35</Age>
            <Height xmlns="">5.9</Height>
            <Birthdate xmlns="">1985-05-20</Birthdate>
            <LastLogin xmlns="">1985-05-20T09:00:00+00:00</LastLogin>
            <WakeupTime xmlns="">06:45:00</WakeupTime>
            <Active xmlns="">false</Active>
          </Person>
        </Address>
      XML

      expect(address.to_xml).to be_xml_equivalent_to(expected_xml)
    end

    it "deserializes from XML with a collection of persons" do
      xml = <<~XML
        <Address xmlns:p="http://example.com/person" xmlns:nsp1="http://example.com/nsp1">
          <Country>USA</Country>
          <PostCode>01001</PostCode>
          <p:Person>
            <nsp1:FirstName>Tom</nsp1:FirstName>
            <nsp1:LastName>Warren</nsp1:LastName>
            <p:Age>40</p:Age>
            <p:Height>5.8</p:Height>
            <p:Birthdate>1980-02-15</p:Birthdate>
            <p:LastLogin>1980-02-15T10:00:00Z</p:LastLogin>
            <p:WakeupTime>07:30:00</p:WakeupTime>
            <p:Active>true</p:Active>
          </p:Person>
          <p:Person>
            <nsp1:FirstName>Jack</nsp1:FirstName>
            <nsp1:LastName>Warren</nsp1:LastName>
            <p:Age>35</p:Age>
            <p:Height>5.9</p:Height>
            <p:Birthdate>1985-05-20</p:Birthdate>
            <p:LastLogin>1985-05-20T09:00:00+00:00</p:LastLogin>
            <p:WakeupTime>06:45:00</p:WakeupTime>
            <p:Active>false</p:Active>
          </p:Person>
        </Address>
      XML

      address_from_xml = described_class.from_xml(xml)
      expect(address_from_xml.country).to eq("USA")
      expect(address_from_xml.post_code).to eq("01001")
      expect(address_from_xml.person.first.first_name).to eq("Tom")
      expect(address_from_xml.person.last.first_name).to eq("Jack")
    end
  end

  describe AddressPersonSpec::Person do
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
          <Age xmlns="">30</Age>
          <Height xmlns="">5.9</Height>
          <Birthdate xmlns="">1990-01-01</Birthdate>
          <LastLogin xmlns="">2023-06-08T10:00:00+00:00</LastLogin>
          <WakeupTime xmlns="">07:00:00</WakeupTime>
          <Active xmlns="">true</Active>
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

      person_1 = persons[0]
      expect(person_1.first_name).to eq("John")
      expect(person_1.age).to eq(30)
      expect(person_1.height).to eq(5.9)
      expect(person_1.birthdate).to eq(Date.parse("1990-01-01"))
      expect(person_1.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
      expect(person_1.wakeup_time).to eq(Time.parse("07:00:00"))
      expect(person_1.active).to be true

      person_2 = persons[1]
      expect(person_2.first_name).to eq("John")
      expect(person_2.age).to eq(30)
      expect(person_2.height).to eq(5.9)
      expect(person_2.birthdate).to eq(Date.parse("1990-01-01"))
      expect(person_2.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
      expect(person_2.wakeup_time).to eq(Time.parse("07:00:00"))
      expect(person_2.active).to be true
    end

    it "serializes to YAML" do
      expect(model.to_yaml).to eq(attributes_yaml.to_yaml)
    end

    it "deserializes from YAML" do
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

    it "deserializes from YAML array" do
      yaml = [attributes_yaml.dup, attributes_yaml.dup].to_yaml

      persons = described_class.from_yaml(yaml)

      person_1 = persons[0]
      expect(person_1.first_name).to eq("John")
      expect(person_1.age).to eq(30)
      expect(person_1.height).to eq(5.9)
      expect(person_1.birthdate).to eq(Date.parse("1990-01-01"))
      expect(person_1.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
      expect(person_1.wakeup_time).to eq(Time.parse("07:00:00"))
      expect(person_1.active).to be true

      person_2 = persons[1]
      expect(person_2.first_name).to eq("John")
      expect(person_2.age).to eq(30)
      expect(person_2.height).to eq(5.9)
      expect(person_2.birthdate).to eq(Date.parse("1990-01-01"))
      expect(person_2.last_login).to eq(DateTime.parse("2023-06-08T10:00:00+00:00"))
      expect(person_2.wakeup_time).to eq(Time.parse("07:00:00"))
      expect(person_2.active).to be true
    end
  end
end
