# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Opal compatibility", if: RUBY_ENGINE == "opal" do
  it "includes Serialize in a class" do
    klass = Class.new { include Lutaml::Model::Serialize }
    expect(klass.include?(Lutaml::Model::Serialize)).to be true
  end

  it "defines attributes and serializes to hash" do
    person = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      attribute :age, :integer
    end

    instance = person.new(name: "Alice", age: 30)
    expect(instance.to_hash).to eq({ "name" => "Alice", "age" => 30 })
  end

  it "round-trips JSON serialization" do
    person = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      attribute :age, :integer
    end

    instance = person.from_json('{"name":"Bob","age":25}')
    expect(instance.name).to eq("Bob")
    expect(instance.age).to eq(25)
  end

  it "handles collections" do
    team = Class.new do
      include Lutaml::Model::Serialize

      attribute :members, :string, collection: true
    end

    instance = team.new(members: %w[Alice Bob Carol])
    expect(instance.members).to eq(%w[Alice Bob Carol])
  end

  it "handles defaults" do
    widget = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      attribute :active, :boolean, default: -> { true }
    end

    instance = widget.new(name: "test")
    expect(instance.active).to be true
  end

  it "handles type coercion" do
    record = Class.new do
      include Lutaml::Model::Serialize

      attribute :count, :integer
      attribute :ratio, :float
      attribute :flag, :boolean
    end

    instance = record.new(count: "42", ratio: "3.14", flag: "true")
    expect(instance.count).to eq(42)
    expect(instance.ratio).to eq(3.14)
    expect(instance.flag).to be true
  end

  it "handles nested models" do
    address = Class.new do
      include Lutaml::Model::Serialize

      attribute :city, :string
      attribute :zip, :string
    end

    person = Class.new do
      include Lutaml::Model::Serialize

      attribute :name, :string
      attribute :address, address
    end

    instance = person.new(name: "Alice",
                          address: address.new(
                            city: "NYC", zip: "10001",
                          ))
    expect(instance.address.city).to eq("NYC")
  end

  it "handles YAML serialization" do
    config = Class.new do
      include Lutaml::Model::Serialize

      attribute :host, :string
      attribute :port, :integer
    end

    instance = config.from_yaml("host: localhost\nport: 8080\n")
    expect(instance.host).to eq("localhost")
    expect(instance.port).to eq(8080)
  end

  it "RuntimeCompatibility detects Opal" do
    expect(Lutaml::Model::RuntimeCompatibility.opal?).to be true
  end

  it "AdapterResolver auto-detects REXML" do
    adapter = Lutaml::Model::AdapterResolver.detect_xml_adapter
    expect(adapter).to eq(:rexml)
  end
end
