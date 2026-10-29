require "spec_helper"

module YamlsSpec
  class Address < Lutaml::Model::Serializable
    attribute :city, :string

    yaml do
      map "city", to: :city
    end
  end

  class Person < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :age, :integer
    attribute :address, Address

    yaml do
      map "full_name", to: :name
      map "age", to: :age
      map "address", to: :address
    end
  end

  class Directory < Lutaml::Model::Collection
    instances :persons, Person

    yamls do
      map_instances to: :persons
    end
  end
end

RSpec.describe "Yamls" do
  let(:john) do
    YamlsSpec::Person.new(
      {
        name: "John",
        age: "30",
        address: YamlsSpec::Address.new({ city: "New York" }),
      },
    )
  end

  let(:jane) do
    YamlsSpec::Person.new(
      {
        name: "Jane",
        age: "25",
        address: YamlsSpec::Address.new({ city: "London" }),
      },
    )
  end

  let(:bob) do
    YamlsSpec::Person.new(
      {
        name: "Bob",
        age: "35",
        address: YamlsSpec::Address.new({ city: "Paris" }),
      },
    )
  end

  let(:valid_yamls) do
    <<~YAMLS.strip
      ---
      full_name: John
      age: 30
      address:
        city: New York
      ---
      full_name: Jane
      age: 25
      address:
        city: London
      ---
      full_name: Bob
      age: 35
      address:
        city: Paris
    YAMLS
  end

  let(:valid_yamls_with_empty_docs) do
    <<~YAMLS
      ---
      full_name: John
      age: 30
      address:
        city: New York
      ---

      ---
      full_name: Jane
      age: 25
      address:
        city: London
      ---


      ---
      full_name: Bob
      age: 35
      address:
        city: Paris
      ---


    YAMLS
  end

  let(:invalid_yamls_content) do
    <<~YAMLS
      ---
      full_name: John
      age: 30
      address:
        city: New York
      ---
      invalid yaml: [
      ---
      full_name: Bob
      age: 35
      address:
        city: Paris
    YAMLS
  end

  let(:parsed) { YamlsSpec::Directory.from_yamls(valid_yamls) }

  it "parses all the yaml documents" do
    expect(parsed.persons).to eq([john, jane, bob])
  end

  it "handles empty documents" do
    expect(
      YamlsSpec::Directory.from_yamls(valid_yamls_with_empty_docs).persons,
    ).to eq([john, jane, bob])
  end

  it "round trips valid yamls correctly" do
    expect(parsed.to_yamls).to eq(valid_yamls)
  end

  it "removes empty documents when round triping valid yamls" do
    expect(
      YamlsSpec::Directory.from_yamls(valid_yamls_with_empty_docs).to_yamls,
    ).to eq(valid_yamls)
  end

  it "skips invalid documents and show warning" do
    expect do
      YamlsSpec::Directory.from_yamls(invalid_yamls_content)
    end.to output(/Skipping invalid yaml: /).to_stderr
  end

  # #1053: a host bundle can rebind ::YAML to another engine (a Psych
  # drop-in), so the multi-doc lane must treat every loaded engine's
  # parse error as a skippable document error — never let a raw engine
  # error escape.
  describe "engine parse errors" do
    it "rescues every loaded YAML engine's parse errors" do
      errors = Lutaml::Model::Utils.yaml_parse_errors

      expect(errors).to include(Psych::SyntaxError)
      if defined?(Yeptris::ParseError)
        expect(errors).to include(Yeptris::ParseError)
      end
    end

    it "skips an invalid document when the active engine raises its own parse error" do
      skip "yeptris not loadable in this process" unless Lutaml::Model::Utils.safe_load("yeptris", :Yeptris)

      allow(YAML).to receive(:load_stream).and_raise(
        Yeptris::ParseError.new("parse failed: unexpected parser state at line 11, column 26"),
      )

      expect do
        expect(Lutaml::Yamls::Adapter::StandardAdapter.parse(invalid_yamls_content)).to eq(
          [
            { "full_name" => "John", "age" => 30, "address" => { "city" => "New York" } },
            { "full_name" => "Bob", "age" => 35, "address" => { "city" => "Paris" } },
          ],
        )
      end.to output(/Skipping invalid yaml: /).to_stderr
    end
  end

  describe "parsing" do
    it "handles empty documents" do
      yamls_with_empty_docs = <<~YAMLS
        ---
        full_name: John
        age: 30
        address:
          city: New York
        ---

        ---
        full_name: Jane
        age: 25
        address:
          city: London
      YAMLS
      result = YamlsSpec::Directory.from_yamls(yamls_with_empty_docs)
      expect(result.persons).to be_an(Array)
      expect(result.persons.length).to eq(2)
    end
  end

  describe "roundtrip" do
    it "maintains data integrity with special characters" do
      special_chars_yamls = <<~YAMLS
        ---
        full_name: John Doe
        age: 30
        address:
          city: New York
        ---
        full_name: Jane "Smith"
        age: 25
        address:
          city: London
      YAMLS

      # Parse the original YAMLS
      directory = YamlsSpec::Directory.from_yamls(special_chars_yamls)

      # Serialize back to YAMLS
      serialized = directory.to_yamls

      # Parse the serialized data again
      roundtrip_directory = YamlsSpec::Directory.from_yamls(serialized)

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
    let(:valid_yamls_content) do
      <<~YAMLS.strip
        ---
        full_name: John
        age: 30
        address:
          city: New York
        ---
        full_name: Jane
        age: 25
        address:
          city: London
        ---
        full_name: Bob
        age: 35
        address:
          city: Paris
      YAMLS
    end

    it "converts between YAMLS and YAML" do
      # Parse YAMLS to Directory
      directory = YamlsSpec::Directory.from_yamls(valid_yamls_content)

      # Convert to YAML
      yaml_string = directory.to_yaml

      # Parse YAML back to Directory
      yaml_directory = YamlsSpec::Directory.from_yaml(yaml_string)

      # Convert back to YAMLS
      yamls_output = yaml_directory.to_yamls

      # Final parse to verify
      final_directory = YamlsSpec::Directory.from_yamls(yamls_output)

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
      directory = YamlsSpec::Directory.new(
        [
          YamlsSpec::Person.new(
            name: "John",
            age: 30,
            address: YamlsSpec::Address.new(city: "New York"),
          ),
          YamlsSpec::Person.new(
            name: "Jane",
            age: 25,
            address: YamlsSpec::Address.new(city: "London"),
          ),
        ],
      )

      # Convert to YAMLS
      yamls_output = directory.to_yamls

      # Parse back to verify
      parsed_directory = YamlsSpec::Directory.from_yamls(yamls_output)

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
