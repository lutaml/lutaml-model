require "spec_helper"
require "lutaml/model"

class SampleModelTag < Lutaml::Model::Serializable
  attribute :text, :string, default: -> { "" }

  xml do
    root "Tag"
    map_content to: :text
  end
end

class Defaults < Lutaml::Model::Serializable
  attribute :name, :string, default: -> { "Anonymous" }
  attribute :age, "Integer", default: -> { 18 }
  attribute :balance, "Decimal", default: -> { BigDecimal("0.0") }
  attribute :tag, SampleModelTag, collection: true
  attribute :preferences, :hash, default: -> { { notifications: true } }
  attribute :status, :string, default: -> { "active" }
  attribute :large_number, :integer, default: -> { 0 }
  attribute :email, :string, default: -> { "example@example.com" }
  attribute :role, :string, values: %w[user admin guest], default: -> { "user" }

  xml do
    root "Defaults"
    map_element "Name", to: :name
    map_element "Age", to: :age
    map_element "Balance", to: :balance
    map_element "Tags", to: :tag
    map_element "Preferences", to: :preferences
    map_element "Status", to: :status
    map_element "LargeNumber", to: :large_number
    map_element "Email", to: :email
    map_element "Role", to: :role
  end

  yaml do
    map "name", to: :name
    map "age", to: :age
  end
end

RSpec.describe Defaults do
  let(:attributes) do
    {
      name: "John Doe",
      age: 30,
      balance: "1234.56",
      tag: [{ "text" => "ruby" }, { "text" => "developer" }],
      preferences: { theme: "dark", notifications: true },
      status: "active",
      large_number: 12345678901234567890,
      email: "john.doe@example.com",
      role: "admin",
    }
  end
  let(:model) { described_class.new(attributes) }

  let(:model_xml) do
    <<~XML
      <Defaults>
        <Name>John Doe</Name>
        <Age>30</Age>
        <Balance>1234.56</Balance>
        <Tags>ruby</Tags>
        <Tags>developer</Tags>
        <Preferences>
          <theme>dark</theme>
          <notifications>true</notifications>
        </Preferences>
        <Status>active</Status>
        <LargeNumber>12345678901234567890</LargeNumber>
        <Email>john.doe@example.com</Email>
        <Role>admin</Role>
      </Defaults>
    XML
  end
  let(:attributes_yaml) do
    {
      "name" => "John Doe",
      "age" => 30,
    }
  end

  it "initializes with default values" do
    default_model = described_class.new
    expect(default_model.name).to eq("Anonymous")
    expect(default_model.age).to eq(18)
    expect(default_model.balance).to eq(BigDecimal("0.0"))
    expect(default_model.tag).to eq([])
    expect(default_model.preferences).to eq({ notifications: true })
    expect(default_model.status).to eq("active")
    expect(default_model.large_number).to eq(0)
    expect(default_model.email).to eq("example@example.com")
    expect(default_model.role).to eq("user")
  end

  it "serializes to XML" do
    expected_xml = model_xml
    expect(model.to_xml).to be_equivalent_to(expected_xml)
  end

  it "deserializes from XML" do
    sample = described_class.from_xml(model_xml)
    expect(sample.name).to eq("John Doe")
    expect(sample.age).to eq(30)
    expect(sample.balance).to eq(BigDecimal("1234.56"))
    expect(sample.tag[0].text).to eq("ruby")
    expect(sample.tag[1].text).to eq("developer")
    expect(sample.preferences).to eq({ "theme" => "dark",
                                       "notifications" => "true" })
    expect(sample.status).to eq("active")
    expect(sample.large_number).to eq(12345678901234567890)
    expect(sample.email).to eq("john.doe@example.com")
    expect(sample.role).to eq("admin")
  end

  it "serializes to JSON" do
    expect(model.to_json).to eq(attributes.to_json)
  end

  it "deserializes from JSON" do
    json = attributes.to_json
    sample = described_class.from_json(json)
    expect(sample.name).to eq("John Doe")
    expect(sample.age).to eq(30)
    expect(sample.balance).to eq(BigDecimal("1234.56"))
    expect(sample.tag[0].text).to eq("ruby")
    expect(sample.tag[1].text).to eq("developer")
    expect(sample.preferences).to eq({ "theme" => "dark",
                                       "notifications" => true })
    expect(sample.status).to eq("active")
    expect(sample.large_number).to eq(12345678901234567890)
    expect(sample.email).to eq("john.doe@example.com")
    expect(sample.role).to eq("admin")
  end

  it "serializes to YAML" do
    expect(model.to_yaml).to eq(attributes_yaml.to_yaml)
  end

  it "deserializes from YAML" do
    yaml = attributes.to_yaml
    sample = described_class.from_yaml(yaml)
    expect(sample.name).to eq("John Doe")
    expect(sample.age).to eq(30)
  end
end
