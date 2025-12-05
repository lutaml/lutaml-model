require "spec_helper"

module RegisterKeyValueSpec
  class GeoCoordinate < Lutaml::Model::Serializable
    attribute :latitude, :float
    attribute :longitude, :float

    json do
      map :lat, to: :latitude
      map :lng, to: :longitude
    end
  end

  class Address < Lutaml::Model::Serializable
    attribute :street, :string
    attribute :city, :string
    attribute :location, GeoCoordinate

    json do
      map :street, to: :street
      map :city, to: :city
      map :geo, to: :location
    end
  end

  class ContactInfo < Lutaml::Model::Serializable
    attribute :phone, :string
    attribute :email, :string

    json do
      map :phoneNumber, to: :phone
      map :email, to: :email
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :age, :integer
    attribute :address, :address
    attribute :contact, :contact_info
    attribute :tags, :string, collection: true

    json do
      map :name, to: :name
      map :age, to: :age
      map :address, to: :address
      map :contactInfo, to: :contact
      map :tags, to: :tags
    end
  end

  class EnhancedContactInfo < Lutaml::Model::Serializable
    attribute :phone, :string
    attribute :email, :string
    attribute :preferred, :boolean

    json do
      map :phoneNumber, to: :phone
      map :email, to: :email
      map :isPrimary, to: :preferred
    end
  end
end

RSpec.describe "RegisterKeyValueSpec" do
  let(:register) { Lutaml::Model::Register.new(:json_test_register) }
  let(:person) do
    RegisterKeyValueSpec::Person.from_json(json, register: register)
  end

  before do
    # Register the registers in the global registry
    Lutaml::Model::GlobalRegister.register(register)

    # Register all the V1 model classes in the register
    register.register_model_tree(RegisterKeyValueSpec::Person)
    register.register_model(RegisterKeyValueSpec::Address)
    register.register_model(RegisterKeyValueSpec::GeoCoordinate)
    register.register_model(RegisterKeyValueSpec::ContactInfo)
  end

  describe "parsing JSON" do
    let(:json) do
      <<~JSON
        {
          "name": "John Doe",
          "age": 30,
          "address": {
            "street": "123 Main St",
            "city": "Anytown",
            "geo": {
              "lat": 40.7128,
              "lng": -74.0060
            }
          },
          "contactInfo": {
            "phoneNumber": "555-1234",
            "email": "john@example.com"
          },
          "tags": ["developer", "musician"]
        }
      JSON
    end

    it "parses JSON into model objects" do
      expect(person).to be_a(RegisterKeyValueSpec::Person)
      expect(person.name).to eq("John Doe")
      expect(person.age).to eq(30)
      expect(person.address).to be_a(RegisterKeyValueSpec::Address)
      expect(person.address.street).to eq("123 Main St")
      expect(person.address.city).to eq("Anytown")
      expect(person.address.location).to be_a(RegisterKeyValueSpec::GeoCoordinate)
      expect(person.address.location.latitude).to eq(40.7128)
      expect(person.address.location.longitude).to eq(-74.0060)
      expect(person.contact).to be_a(RegisterKeyValueSpec::ContactInfo)
      expect(person.contact.phone).to eq("555-1234")
      expect(person.contact.email).to eq("john@example.com")
      expect(person.tags).to eq(["developer", "musician"])
    end

    it "serializes model objects back to JSON" do
      json_output = person.to_json
      parsed_json = JSON.parse(json_output)

      expect(parsed_json["name"]).to eq("John Doe")
      expect(parsed_json["age"]).to eq(30)
      expect(parsed_json["address"]["street"]).to eq("123 Main St")
      expect(parsed_json["address"]["city"]).to eq("Anytown")
      expect(parsed_json["address"]["geo"]["lat"]).to eq(40.7128)
      expect(parsed_json["address"]["geo"]["lng"]).to eq(-74.0060)
      expect(parsed_json["contactInfo"]["phoneNumber"]).to eq("555-1234")
      expect(parsed_json["contactInfo"]["email"]).to eq("john@example.com")
      expect(parsed_json["tags"]).to eq(["developer", "musician"])
    end
  end

  describe "using global type substitution with JSON" do
    let(:register_substitution) do
      register.register_global_type_substitution(
        from_type: RegisterKeyValueSpec::ContactInfo,
        to_type: RegisterKeyValueSpec::EnhancedContactInfo,
      )
    end

    let(:json) do
      <<~JSON
        {
          "name": "Jane Smith",
          "age": 28,
          "address": {
            "street": "456 Oak Ave",
            "city": "Somewhere",
            "geo": {
              "lat": 37.7749,
              "lng": -122.4194
            }
          },
          "contactInfo": {
            "phoneNumber": "555-5678",
            "email": "jane@example.com",
            "isPrimary": true
          },
          "tags": ["designer"]
        }
      JSON
    end

    context "when the substitute class is not registered" do
      it "deserializes contactInfo using ContactInfo class" do
        expect(person.contact).to be_a(RegisterKeyValueSpec::ContactInfo)
        expect(person.contact).not_to respond_to(:preferred)
        expect(person.contact.phone).to eq("555-5678")
        expect(person.contact.email).to eq("jane@example.com")
      end
    end

    context "when the substitute class is registered" do
      it "deserializes contactInfo using EnhancedContactInfo class" do
        register.register_model(RegisterKeyValueSpec::EnhancedContactInfo)
        register_substitution

        enhanced_person = RegisterKeyValueSpec::Person.from_json(json,
                                                                 register: register.id)

        expect(enhanced_person.contact).to be_a(RegisterKeyValueSpec::EnhancedContactInfo)
        expect(enhanced_person.contact).to respond_to(:preferred)
        expect(enhanced_person.contact.phone).to eq("555-5678")
        expect(enhanced_person.contact.email).to eq("jane@example.com")
        expect(enhanced_person.contact.preferred).to be(true)

        # Ensure serialization includes the new field
        json_output = enhanced_person.to_json
        parsed_json = JSON.parse(json_output)
        expect(parsed_json["contactInfo"]["isPrimary"]).to be(true)
      end
    end
  end

  describe "handling complex nested JSON arrays" do
    let(:complex_json) do
      <<~JSON
        {
          "name": "Team Alpha",
          "members": [
            {
              "name": "Alice",
              "age": 32,
              "address": {
                "street": "789 Pine St",
                "city": "Elsewhere"
              }
            },
            {
              "name": "Bob",
              "age": 29,
              "address": {
                "street": "321 Elm St",
                "city": "Nowhere"
              }
            }
          ]
        }
      JSON
    end

    before do
      stub_const("RegisterKeyValueSpec::Team", Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        attribute :members, :person, collection: true

        json do
          map :name, to: :name
          map :members, to: :members
        end
      end)

      register.register_model(RegisterKeyValueSpec::Team)
    end

    it "correctly handles arrays of complex objects" do
      team = RegisterKeyValueSpec::Team.from_json(complex_json,
                                                  register: register)

      expect(team.name).to eq("Team Alpha")
      expect(team.members.size).to eq(2)
      expect(team.members[0].name).to eq("Alice")
      expect(team.members[0].age).to eq(32)
      expect(team.members[0].address.street).to eq("789 Pine St")
      expect(team.members[1].name).to eq("Bob")
      expect(team.members[1].age).to eq(29)
      expect(team.members[1].address.street).to eq("321 Elm St")

      # Test round-trip serialization
      toml_output = team.to_toml
      team2 = RegisterKeyValueSpec::Team.from_toml(toml_output,
                                                   register: register)

      expect(team2).to eq(team)
      expect(team2.members[0].name).to eq("Alice")
      expect(team2.members[1].name).to eq("Bob")
    end
  end

  describe "#resolve" do
    before do
      stub_const("RegisterKeyValueSpec::Team",
                 Class.new(Lutaml::Model::Serializable))
      register.register_model(RegisterKeyValueSpec::Team)
    end

    it "resolves a class" do
      expect(register.resolve("RegisterKeyValueSpec::Team")).to eq(RegisterKeyValueSpec::Team)
      expect(register.resolve(:"RegisterKeyValueSpec::Team")).to eq(RegisterKeyValueSpec::Team)
      expect(register.resolve(RegisterKeyValueSpec::Team)).to eq(RegisterKeyValueSpec::Team)
    end

    it "returns nil for an unknown class" do
      expect(register.resolve("UnknownClass")).to be_nil
    end
  end
end
