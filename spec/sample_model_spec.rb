# spec/sample_model_spec.rb
require "spec_helper"
require_relative "fixtures/sample_model"

RSpec.describe SampleModel do
  let(:attributes) {
    {
      name: "John Doe",
      age: 30,
      balance: "1234.56",
      tags: ["ruby", "developer"],
      preferences: { theme: "dark", notifications: true },
      uuid: "123e4567-e89b-12d3-a456-426614174000",
      status: :active,
      large_number: "12345678901234567890",
      avatar: "binary data",
      website: "http://example.com",
      email: "john.doe@example.com",
      ip_address: "192.168.1.1",
      metadata: '{"key":"value"}',
      role: "admin",
    }
  }
  let(:model) { SampleModel.new(attributes) }

  it "initializes with default values" do
    default_model = SampleModel.new
    expect(default_model.name).to eq("Anonymous")
    expect(default_model.age).to eq(18)
    expect(default_model.balance).to eq(BigDecimal("0.0"))
    expect(default_model.tags).to eq([])
    expect(default_model.preferences).to eq({ notifications: true })
    expect(default_model.uuid).to be_a(String)
    expect(default_model.status).to eq(:active)
    expect(default_model.large_number).to eq(0)
    expect(default_model.avatar).to eq("")
    expect(default_model.website).to eq(URI.parse("http://example.com"))
    expect(default_model.email).to eq("example@example.com")
    expect(default_model.ip_address).to eq(IPAddr.new("127.0.0.1"))
    expect(default_model.metadata).to eq({})
    expect(default_model.role).to eq("user")
  end

  it "serializes to XML" do
    expected_xml = Nokogiri::XML::Builder.new do |xml|
      xml.SampleModel {
        xml.Name "John Doe"
        xml.Age "30"
        xml.Balance "1234.56"
        xml.Tags '["ruby","developer"]'
        xml.Preferences '{"theme":"dark","notifications":true}'
        xml.UUID "123e4567-e89b-12d3-a456-426614174000"
        xml.Status "active"
        xml.LargeNumber "12345678901234567890"
        xml.Avatar "binary data"
        xml.Website "http://example.com"
        xml.Email "john.doe@example.com"
        xml.IPAddress "192.168.1.1"
        xml.Metadata '{"key":"value"}'
        xml.Role "admin"
      }
    end.to_xml
    expect(Nokogiri::XML(model.to_xml).to_s).to eq(Nokogiri::XML(expected_xml).to_s)
  end

  it "deserializes from XML" do
    xml = Nokogiri::XML::Builder.new do |xml|
      xml.SampleModel {
        xml.Name "John Doe"
        xml.Age "30"
        xml.Balance "1234.56"
        xml.Tags '["ruby","developer"]'
        xml.Preferences '{"theme":"dark","notifications":true}'
        xml.UUID "123e4567-e89b-12d3-a456-426614174000"
        xml.Status "active"
        xml.LargeNumber "12345678901234567890"
        xml.Avatar "binary data"
        xml.Website "http://example.com"
        xml.Email "john.doe@example.com"
        xml.IPAddress "192.168.1.1"
        xml.Metadata '{"key":"value"}'
        xml.Role "admin"
      }
    end.to_xml
    sample = SampleModel.from_xml(xml)
    expect(sample.name).to eq("John Doe")
    expect(sample.age).to eq(30)
    expect(sample.balance).to eq(BigDecimal("1234.56"))
    expect(sample.tags).to eq(["ruby", "developer"])
    expect(sample.preferences).to eq({ "theme" => "dark", "notifications" => true })
    expect(sample.uuid).to eq("123e4567-e89b-12d3-a456-426614174000")
    expect(sample.status).to eq(:active)
    expect(sample.large_number).to eq(12345678901234567890)
    expect(sample.avatar).to eq("binary data")
    expect(sample.website).to eq(URI.parse("http://example.com"))
    expect(sample.email).to eq("john.doe@example.com")
    expect(sample.ip_address).to eq(IPAddr.new("192.168.1.1"))
    expect(sample.metadata).to eq({ "key" => "value" })
    expect(sample.role).to eq("admin")
  end

  it "serializes to JSON" do
    expect(model.to_json).to eq(attributes.to_json)
  end

  it "deserializes from JSON" do
    json = attributes.to_json
    sample = SampleModel.from_json(json)
    expect(sample.name).to eq("John Doe")
    expect(sample.age).to eq(30)
    expect(sample.balance).to eq(BigDecimal("1234.56"))
    expect(sample.tags).to eq(["ruby", "developer"])
    expect(sample.preferences).to eq({ "theme" => "dark", "notifications" => true })
    expect(sample.uuid).to eq("123e4567-e89b-12d3-a456-426614174000")
    expect(sample.status).to eq(:active)
    expect(sample.large_number).to eq(12345678901234567890)
    expect(sample.avatar).to eq("binary data")
    expect(sample.website).to eq(URI.parse("http://example.com"))
    expect(sample.email).to eq("john.doe@example.com")
    expect(sample.ip_address).to eq(IPAddr.new("192.168.1.1"))
    expect(sample.metadata).to eq({ "key" => "value" })
    expect(sample.role).to eq("admin")
  end

  let(:attributes_yaml) {
    {
      "name" => "John Doe",
      "age" => 30,
    }
  }
  it "serializes to YAML" do
    expect(model.to_yaml).to eq(attributes_yaml.to_yaml)
  end

  it "deserializes from YAML" do
    yaml = attributes.to_yaml
    sample = SampleModel.from_yaml(yaml)
    expect(sample.name).to eq("John Doe")
    expect(sample.age).to eq(30)
  end
end
