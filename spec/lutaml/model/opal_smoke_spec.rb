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

  it "resolves scalar union attributes" do
    reading = Class.new do
      include Lutaml::Model::Serialize

      attribute :value, %i[integer string]
    end

    expect(reading.from_json('{"value":42}').value).to eq(42)
    expect(reading.from_json('{"value":"hot"}').value).to eq("hot")
  end

  it "resolves a union of a model member and a scalar" do
    temperature = Class.new do
      include Lutaml::Model::Serialize

      attribute :celsius, :float
    end
    holder = Class.new do
      include Lutaml::Model::Serialize

      attribute :temp, [temperature, :string]
    end

    structured = holder.from_json('{"temp":{"celsius":12.5}}')
    expect(structured.temp).to be_a(temperature)
    expect(structured.temp.celsius).to eq(12.5)
    expect(holder.from_json('{"temp":"cold"}').temp).to eq("cold")
  end

  it "validates a pattern on a union :string member" do
    coded = Class.new do
      include Lutaml::Model::Serialize

      attribute :code, %i[integer string], pattern: /\A[A-Z]+\z/
    end

    expect(coded.new(code: "ABC").validate).to be_empty
    expect(coded.new(code: "abc").validate).not_to be_empty
    expect(coded.new(code: 42).validate).to be_empty
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

  it "AdapterResolver auto-detects Oga as the default" do
    adapter = Lutaml::Model::AdapterResolver.detect_xml_adapter
    expect(adapter).to eq(:oga)
  end

  it "exposes both Oga and REXML as available adapters under Opal" do
    # Both are pure Ruby; Nokogiri and Ox are C extensions and excluded.
    options = Lutaml::Model::FormatRegistry.adapter_options_for(:xml)
    expect(options).not_to be_nil

    available = options[:available]
    expect(available).to include(:oga, :rexml)
    expect(available).not_to include(:nokogiri, :ox)
  end

  # Opal's Module#prepend raises "Prepending a module multiple times
  # is not supported" on the second call; runtime_compatibility.rb
  # patches it to match MRI's idempotent behavior. Top-level lib files
  # (lib/lutaml/model.rb, lib/lutaml/xml.rb) rely on this when Opal's
  # eager loader re-evaluates them.
  it "Module#prepend is idempotent under Opal" do
    mod = Module.new
    klass = Class.new
    klass.prepend(mod)

    expect { klass.prepend(mod) }.not_to raise_error
    expect(klass.ancestors.count(mod)).to eq(1)
  end
end
