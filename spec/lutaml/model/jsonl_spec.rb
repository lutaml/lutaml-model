require "spec_helper"

module JsonlSpec
  class Address < Lutaml::Model::Serializable
    attribute :city, :string

    jsonl do
      map "city", to: :city
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :age, :integer
    attribute :address, Address

    jsonl do
      map "name", to: :name
      map "age", to: :age
      map "address", to: :address
    end
  end

  class Directory < Lutaml::Model::Serializable
    attribute :persons, Person, collection: true

    jsonl do
      map to: :persons
    end
  end
end

RSpec.describe "Jsonl" do
  let(:john) do
    JsonlSpec::Person.new(
      {
        name: "John",
        age: "30",
        address: JsonlSpec::Address.new({ city: "New York" }),
      },
    )
  end

  let(:jane) do
    JsonlSpec::Person.new(
      {
        name: "Jane",
        age: "25",
        address: JsonlSpec::Address.new({ city: "London" }),
      },
    )
  end

  let(:bob) do
    JsonlSpec::Person.new(
      {
        name: "Bob",
        age: "35",
        address: JsonlSpec::Address.new({ city: "Paris" }),
      },
    )
  end

  let(:valid_jsonl) do
    <<~JSONL.strip
      {"name":"John","age":30,"address":{"city":"New York"}}
      {"name":"Jane","age":25,"address":{"city":"London"}}
      {"name":"Bob","age":35,"address":{"city":"Paris"}}
    JSONL
  end

  let(:valid_jsonl_with_empty_lines) do
    <<~JSONL
      {"name":"John","age":30,"address":{"city":"New York"}}

      {"name":"Jane","age":25,"address":{"city":"London"}}


      {"name":"Bob","age":35,"address":{"city":"Paris"}}


    JSONL
  end

  let(:invalid_jsonl_content) do
    <<~JSONL
      {"name": "John", "age": 30, "address": {"city": "New York"}}
      invalid json
      {"name": "Bob", "age": 35, "address": {"city": "Paris"}}
    JSONL
  end

  let(:parsed) { JsonlSpec::Directory.from_jsonl(valid_jsonl) }

  it "parses all the json lines" do
    expect(parsed.persons).to eq([john, jane, bob])
  end

  it "handles empty lines" do
    expect(
      JsonlSpec::Directory.from_jsonl(valid_jsonl_with_empty_lines).persons,
    ).to eq([john, jane, bob])
  end

  it "round trips valid jsonl correctly" do
    expect(parsed.to_jsonl).to eq(valid_jsonl)
  end

  it "removes empty line when round triping valid jsonl" do
    expect(
      JsonlSpec::Directory.from_jsonl(valid_jsonl_with_empty_lines).to_jsonl,
    ).to eq(valid_jsonl)
  end

  it "skips invalid lines and show warning" do
    warning_msg = <<~MSG
      Skipping invalid line: unexpected character: 'invalid json'
    MSG

    expect do
      JsonlSpec::Directory.from_jsonl(invalid_jsonl_content)
    end.to output(warning_msg).to_stderr
  end

  describe "parsing" do
    it "handles empty lines" do
      jsonl_with_empty_lines = <<~JSONL
        {"name": "John", "age": 30, "address": {"city": "New York"}}

        {"name": "Jane", "age": 25, "address": {"city": "London"}}
      JSONL
      result = JsonlSpec::Directory.from_jsonl(jsonl_with_empty_lines)
      expect(result.persons).to be_an(Array)
      expect(result.persons.length).to eq(2)
    end
  end

  describe "roundtrip" do
    it "maintains data integrity with special characters" do
      special_chars_jsonl = <<~JSONL
        {"name": "John Doe", "age": 30, "address": {"city": "New York"}}
        {"name": "Jane \\"Smith\\"", "age": 25, "address": {"city": "London"}}
      JSONL

      # Parse the original JSONL
      directory = JsonlSpec::Directory.from_jsonl(special_chars_jsonl)

      # Serialize back to JSONL
      serialized = directory.to_jsonl

      # Parse the serialized data again
      roundtrip_directory = JsonlSpec::Directory.from_jsonl(serialized)

      # Compare the results
      expect(roundtrip_directory.persons.length).to eq(directory.persons.length)
      roundtrip_directory.persons.each_with_index do |person, index|
        original = directory.persons[index]
        expect(person.name).to eq(original.name)
        expect(person.age).to eq(original.age)
        expect(person.address.city).to eq(original.address.city)
      end
    end
  end

  describe "format conversion" do
    let(:valid_jsonl_content) do
      <<~JSONL.strip
        {"name":"John","age":30,"address":{"city":"New York"}}
        {"name":"Jane","age":25,"address":{"city":"London"}}
        {"name":"Bob","age":35,"address":{"city":"Paris"}}
      JSONL
    end

    it "converts between JSONL and JSON" do
      # Parse JSONL to Directory
      directory = JsonlSpec::Directory.from_jsonl(valid_jsonl_content)

      # Convert to JSON
      json_string = directory.to_json

      # Parse JSON back to Directory
      json_directory = JsonlSpec::Directory.from_json(json_string)

      # Convert back to JSONL
      jsonl_output = json_directory.to_jsonl

      # Final parse to verify
      final_directory = JsonlSpec::Directory.from_jsonl(jsonl_output)

      # Compare the results
      expect(final_directory.persons.length).to eq(directory.persons.length)
      final_directory.persons.each_with_index do |person, index|
        original = directory.persons[index]
        expect(person.name).to eq(original.name)
        expect(person.age).to eq(original.age)
        expect(person.address.city).to eq(original.address.city)
      end
    end

    it "handles collections of objects" do
      # Create a directory with people
      directory = JsonlSpec::Directory.new(
        persons: [
          JsonlSpec::Person.new(
            name: "John",
            age: 30,
            address: JsonlSpec::Address.new(city: "New York"),
          ),
          JsonlSpec::Person.new(
            name: "Jane",
            age: 25,
            address: JsonlSpec::Address.new(city: "London"),
          ),
        ],
      )

      # Convert to JSONL
      jsonl_output = directory.to_jsonl

      # Parse back to verify
      parsed_directory = JsonlSpec::Directory.from_jsonl(jsonl_output)

      # Compare the results
      expect(parsed_directory.persons.length).to eq(directory.persons.length)
      parsed_directory.persons.each_with_index do |person, index|
        original = directory.persons[index]
        expect(person.name).to eq(original.name)
        expect(person.age).to eq(original.age)
        expect(person.address.city).to eq(original.address.city)
      end
    end
  end
end
