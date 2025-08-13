module SerializeableSpec
  class TestModel
    attr_accessor :name, :age

    def initialize(name: nil, age: nil)
      @name = name
      @age = age
    end
  end

  class TestModelMapper < Lutaml::Model::Serializable
    model TestModel

    attribute :name, Lutaml::Model::Type::String
    attribute :age, Lutaml::Model::Type::String
  end

  class TestMapper < Lutaml::Model::Serializable
    attribute :name, Lutaml::Model::Type::String
    attribute :age, Lutaml::Model::Type::String

    yaml do
      map :na, to: :name
      map :ag, to: :age
    end
  end

  class KeyValueMapper < Lutaml::Model::Serializable
    attribute :first_name, :string
    attribute :last_name, :string
    attribute :age, :integer

    key_value do
      map :first_name, to: :first_name
      map :last_name, to: :last_name
      map :age, to: :age
    end
  end

  ### XML root mapping

  class RecordDate < Lutaml::Model::Serializable
    attribute :content, :string

    xml do
      root "recordDate"
      map_content to: :content
    end
  end

  class OriginInfo < Lutaml::Model::Serializable
    attribute :date_issued, RecordDate, collection: true

    xml do
      root "originInfo"
      map_element "dateIssued", to: :date_issued
    end
  end

  ### Enumeration

  class Ceramic < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :firing_temperature, :integer
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :featured_piece,
              Ceramic,
              values: [
                Ceramic.new(type: "Porcelain", firing_temperature: 1300),
                Ceramic.new(type: "Stoneware", firing_temperature: 1200),
                Ceramic.new(type: "Earthenware", firing_temperature: 1000),
              ]
  end

  class GlazeTechnique < Lutaml::Model::Serializable
    attribute :name, :string, values: ["Celadon", "Raku", "Majolica"]
  end

  class TranslateHelper < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :path, :string
    attribute :name, :string
  end

  class TranslateMappings < Lutaml::Model::Serializable
    attribute :translate, TranslateHelper, collection: true

    key_value do
      map "translate", to: :translate, child_mappings:
                                        {
                                          id: :key,
                                          path: %i[path link],
                                          name: %i[path name],
                                        }
    end
  end

  ### Single option serialization

  class SingleOptionModel < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :age, :integer
    attribute :phone, :string
    attribute :address, :string

    json do
      map "name", to: :name
      map "age", to: :age
      map "phone", to: :phone, with: { to: :phone_to_json }
      map "address", to: :address, with: { from: :address_from_json }
    end

    xml do
      root "person"
      map_element "name", to: :name
      map_element "age", to: :age
      map_element "phone", to: :phone, with: { to: :phone_to_xml }
      map_element "address", to: :address, with: { from: :address_from_xml }
    end

    yaml do
      map "name", to: :name
      map "age", to: :age
      map "phone", to: :phone, with: { to: :phone_to_json }
      map "address", to: :address, with: { from: :address_from_json }
    end

    key_value do
      map "name", to: :name
      map "age", to: :age
      map "phone", to: :phone, with: { to: :phone_to_json }
      map "address", to: :address, with: { from: :address_from_json }
    end

    def phone_to_json(model, doc)
      doc["phone"] = "+1-#{model.phone}"
    end

    def address_from_json(model, value)
      model.address = value.sub(/^Address: /, "")
    end

    def phone_to_xml(model, parent, doc)
      el = doc.create_element("phone")
      doc.add_text(el, "+1-#{model.phone}")
      doc.add_element(parent, el)
    end

    def address_from_xml(model, value)
      model.address = value.text.sub(/^Address: /, "")
    end
  end
end

RSpec.describe Lutaml::Model::Serializable do
  describe ".model" do
    it "sets the model for the class" do
      expect do
        described_class.model(SerializeableSpec::TestModel)
      end.to change(
        described_class, :model
      )
        .from(described_class)
        .to(SerializeableSpec::TestModel)
    end
  end

  describe ".attribute" do
    before do
      stub_const("TestClass", Class.new(described_class))
    end

    context "when method_name is given" do
      let(:attribute) do
        TestClass.attribute("test", method: :foobar)
      end

      it "adds derived attribute" do
        expect { attribute }
          .to change { TestClass.attributes["test"] }
          .from(nil)
          .to(Lutaml::Model::Attribute)
      end

      it "returns true for derived?" do
        expect(attribute.derived?).to be(true)
      end
    end

    context "when type is given" do
      let(:attribute) do
        TestClass.attribute("foo", Lutaml::Model::Type::String)
      end

      it "adds the attribute and getter setter for that attribute" do
        expect { attribute }
          .to change { TestClass.attributes.keys }.from([]).to(["foo"])
          .and change { TestClass.new.respond_to?(:foo) }.from(false).to(true)
          .and change { TestClass.new.respond_to?(:foo=) }.from(false).to(true)
      end

      it "returns false for derived?" do
        expect(attribute.derived?).to be(false)
      end
    end
  end

  describe ".restrict" do
    before do
      stub_const("RestrictTestClass", Class.new(described_class))
      RestrictTestClass.attribute(:foo, :string, collection: 1..3, values: [1, 2, 3])
    end

    it "merges new options into the attribute's options" do
      expect { RestrictTestClass.restrict(:foo, collection: 2..4) }
        .to change { RestrictTestClass.attributes[:foo].options[:collection] }
        .from(1..3).to(2..4)

      expect(RestrictTestClass.attributes[:foo].options[:values]).to eq([1, 2, 3])
    end

    it "does not remove existing options not specified in restrict" do
      RestrictTestClass.restrict(:foo, collection: 5..6, values: [4, 5, 6])
      expect(RestrictTestClass.attributes[:foo].options[:collection]).to eq(5..6)
      expect(RestrictTestClass.attributes[:foo].options[:values]).to eq([4, 5, 6])
    end

    it "raises an error for invalid options" do
      expect { RestrictTestClass.restrict(:foo, new_option: :bar) }
        .to raise_error(Lutaml::Model::InvalidAttributeOptionsError, "Invalid options given for `foo` [:new_option]")
    end

    it "raises an error if the attribute does not exist" do
      expect { RestrictTestClass.restrict(:bar, collection: 1..2) }
        .to raise_error(NoMethodError)
    end
  end

  describe ".mappings_for" do
    context "when mapping is defined" do
      it "returns the defined mapping" do
        actual_mappings = SerializeableSpec::TestMapper.mappings_for(:yaml).mappings

        expect(actual_mappings[0].name).to eq(:na)
        expect(actual_mappings[0].to).to eq(:name)

        expect(actual_mappings[1].name).to eq(:ag)
        expect(actual_mappings[1].to).to eq(:age)
      end
    end

    context "when mapping is not defined" do
      it "maps attributes to mappings" do
        allow(SerializeableSpec::TestMapper.mappings).to receive(:[]).with(:yaml).and_return(nil)

        actual_mappings = SerializeableSpec::TestMapper.mappings_for(:yaml).mappings

        expect(actual_mappings[0].name).to eq("name")
        expect(actual_mappings[0].to).to eq(:name)

        expect(actual_mappings[1].name).to eq("age")
        expect(actual_mappings[1].to).to eq(:age)
      end
    end
  end

  # TODO: Move to key_value_transform specs
  # describe ".translate_mappings" do
  #   let(:child_mappings) do
  #     {
  #       id: :key,
  #       path: %i[path link],
  #       name: %i[path name],
  #     }
  #   end

  #   let(:hash) do
  #     {
  #       "foo" => {
  #         "path" => {
  #           "link" => "link one",
  #           "name" => "one",
  #         },
  #       },
  #       "abc" => {
  #         "path" => {
  #           "link" => "link two",
  #           "name" => "two",
  #         },
  #       },
  #       "hello" => {
  #         "path" => {
  #           "link" => "link three",
  #           "name" => "three",
  #         },
  #       },
  #     }
  #   end

  #   let(:attr) { SerializeableSpec::TranslateMappings.attributes[:translate] }

  #   let(:expected_value) do
  #     [
  #       SerializeableSpec::TranslateHelper.new({
  #                                                "id" => "foo",
  #                                                "name" => "one",
  #                                                "path" => "link one",
  #                                              }),
  #       SerializeableSpec::TranslateHelper.new({
  #                                                "id" => "abc",
  #                                                "name" => "two",
  #                                                "path" => "link two",
  #                                              }),
  #       SerializeableSpec::TranslateHelper.new({
  #                                                "id" => "hello",
  #                                                "name" => "three",
  #                                                "path" => "link three",
  #                                              }),
  #     ]
  #   end

  #   it "generates hash based on child_mappings" do
  #     actual_value = described_class.translate_mappings(hash, child_mappings, attr, :yaml)

  #     expect(actual_value.map { |obj| [obj.id, obj.name, obj.path] })
  #       .to eq(expected_value.map { |obj| [obj.id, obj.name, obj.path] })
  #   end
  # end

  describe "#key_value" do
    let(:model) { SerializeableSpec::KeyValueMapper }

    Lutaml::Model::Config::KEY_VALUE_FORMATS.each do |format|
      it "defines 3 mappings for #{format}" do
        expect(model.mappings_for(format).mappings.count).to eq(3)
      end

      it "defines mappings correctly for #{format}" do
        defined_mappings = model.mappings_for(format).mappings.map(&:name)

        expect(defined_mappings).to eq(%i[first_name last_name age])
      end
    end
  end

  describe "XML root name override" do
    it "uses root name defined at the component class" do
      record_date = SerializeableSpec::RecordDate.new(content: "2021-01-01")
      expected_xml = "<recordDate>2021-01-01</recordDate>"
      expect(record_date.to_xml).to eq(expected_xml)
    end

    it "uses mapped element name at the aggregating class, overriding root name" do
      origin_info = SerializeableSpec::OriginInfo.new(date_issued: [SerializeableSpec::RecordDate.new(content: "2021-01-01")])
      expected_xml = <<~XML
        <originInfo><dateIssued>2021-01-01</dateIssued></originInfo>
      XML
      expect(origin_info.to_xml).to be_equivalent_to(expected_xml)
    end
  end

  describe "String enumeration" do
    context "when assigning an invalid value" do
      it "raises an error after creation after validate" do
        glaze = SerializeableSpec::GlazeTechnique.new(name: "Celadon")
        glaze.name = "Tenmoku"
        expect do
          glaze.validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::InvalidValueError)
          expect(error.error_messages).to include("name is `Tenmoku`, must be one of the following [Celadon, Raku, Majolica]")
        end
      end
    end

    context "when assigning a valid value" do
      it "changes the value after creation" do
        glaze = SerializeableSpec::GlazeTechnique.new(name: "Celadon")
        glaze.name = "Raku"
        expect(glaze.name).to eq("Raku")
      end

      it "assigns the value during creation" do
        glaze = SerializeableSpec::GlazeTechnique.new(name: "Majolica")
        expect(glaze.name).to eq("Majolica")
      end
    end
  end

  describe "Serializable object enumeration" do
    context "when assigning an invalid value" do
      it "raises ValidationError containing InvalidValueError after creation" do
        glaze = SerializeableSpec::GlazeTechnique.new(name: "Celadon")
        glaze.name = "Tenmoku"
        expect do
          glaze.validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::InvalidValueError)
          expect(error.error_messages).to include(a_string_matching(/name is `Tenmoku`, must be one of the following/))
        end
      end

      it "raises ValidationError containing InvalidValueError during creation" do
        expect do
          SerializeableSpec::GlazeTechnique.new(name: "Crystalline").validate!
        end.to raise_error(Lutaml::Model::ValidationError) do |error|
          expect(error).to include(Lutaml::Model::InvalidValueError)
          expect(error.error_messages).to include(a_string_matching(/name is `Crystalline`, must be one of the following/))
        end
      end
    end

    context "when assigning a valid value" do
      it "changes the value after creation" do
        collection = SerializeableSpec::CeramicCollection.new(
          featured_piece: SerializeableSpec::Ceramic.new(type: "Porcelain",
                                                         firing_temperature: 1300),
        )
        collection.featured_piece = SerializeableSpec::Ceramic.new(type: "Stoneware",
                                                                   firing_temperature: 1200)
        expect(collection.featured_piece.type).to eq("Stoneware")
      end

      it "assigns the value during creation" do
        collection = SerializeableSpec::CeramicCollection.new(
          featured_piece: SerializeableSpec::Ceramic.new(type: "Earthenware",
                                                         firing_temperature: 1000),
        )
        expect(collection.featured_piece.type).to eq("Earthenware")
      end
    end
  end

  describe "Single option serialization" do
    let(:attributes) do
      {
        name: "John Doe",
        age: 30,
        phone: "123-456-7890",
        address: "123 Main St",
      }
    end

    let(:model) { SerializeableSpec::SingleOptionModel.new(attributes) }

    describe "JSON serialization" do
      let(:expected_json) do
        {
          name: "John Doe",
          age: 30,
          phone: "+1-123-456-7890",
          address: "123 Main St",
        }.to_json
      end

      let(:parsed) do
        SerializeableSpec::SingleOptionModel.from_json(
          {
            name: "John Doe",
            age: 30,
            phone: "123-456-7890",
            address: "Address: 123 Main St",
          }.to_json,
        )
      end

      it "serializes to JSON with custom name transformation" do
        expect(model.to_json).to eq(expected_json)
      end

      it "deserializes from JSON with custom name transformation" do
        expect(parsed).to eq(model)
      end
    end

    describe "XML serialization" do
      let(:expected_xml) do
        <<~XML
          <person>
            <name>John Doe</name>
            <age>30</age>
            <phone>+1-123-456-7890</phone>
            <address>123 Main St</address>
          </person>
        XML
      end

      let(:parsed) do
        SerializeableSpec::SingleOptionModel.from_xml <<~XML
          <person>
            <name>John Doe</name>
            <age>30</age>
            <phone>123-456-7890</phone>
            <address>Address: 123 Main St</address>
          </person>
        XML
      end

      it "serializes to XML with custom name transformation" do
        expect(model.to_xml).to be_equivalent_to(expected_xml)
      end

      it "deserializes from XML with custom name transformation" do
        expect(parsed).to eq(model)
      end
    end
  end

  describe "InvalidFormatError handling" do
    let(:invalid_data) do
      {
        xml: {
          nokogiri: "<<<<name>John Doe</name>",
          ox: "<<<<name>John Doe</name>",
          oga: '<person xmlns="http://example.com" xmlns="http://another.com"><name>John Doe</name></person>',
        },
        json: {
          standard_json: '{"name": "John", "age": 30,}',
        },
        yaml: {
          standard_yaml: "name: \"John Doe\nage: 30",
        },
        toml: {
          toml_rb: 'name = "John Doe\nage = 30',
        },
        hash: {
          standard_hash: "This is not a hash",
        },
      }
    end

    shared_examples "invalid format error" do |format, adapter, method, config_key|
      around do |example|
        old_adapter = Lutaml::Model::Config.send("#{config_key}_adapter")
        Lutaml::Model::Config.send("#{config_key}_adapter_type=", adapter)

        example.run
      ensure
        Lutaml::Model::Config.send("#{config_key}_adapter=", old_adapter)
      end

      it "raises InvalidFormatError for invalid #{adapter.to_s.capitalize} #{format.to_s.upcase}" do
        data = invalid_data[format][adapter]
        expect do
          SerializeableSpec::SingleOptionModel.public_send(method, data)
        end.to raise_error(Lutaml::Model::InvalidFormatError) do |error|
          expect(error.message).to include("`#{format}`")
          expect(error.message).to include("input format is invalid")
        end
      end
    end

    describe "invalid format handling for XML" do
      it_behaves_like "invalid format error", :xml, :nokogiri, :from_xml, :xml
      it_behaves_like "invalid format error", :xml, :ox, :from_xml, :xml
      it_behaves_like "invalid format error", :xml, :oga, :from_xml, :xml
    end

    describe "invalid format handling for invalid JSON" do
      it_behaves_like "invalid format error", :json, :standard_json, :from_json, :json
    end

    describe "invalid format handling for invalid YAML" do
      it_behaves_like "invalid format error", :yaml, :standard_yaml, :from_yaml, :yaml
    end

    describe "invalid format handling for invalid TOML" do
      it_behaves_like "invalid format error", :toml, :toml_rb, :from_toml, :toml

      # Only test Tomlib if not on problematic platform (Windows Ruby < 3.3)
      if RUBY_PLATFORM.include?("mingw") && RUBY_VERSION < "3.3"
        # NOTE: Skipped Tomlib case because it causes segmentation fault on
        # Windows with Ruby < 3.3
        it "skips Tomlib test on Windows Ruby < 3.3 due to segfault risk" do
          skip "Tomlib causes segmentation faults on Windows with Ruby < 3.3 " \
               "when parsing invalid TOML"
        end
      else
        it_behaves_like "invalid format error", :toml, :tomlib, :from_toml, :toml
      end
    end

    describe "invalid format handling for invalid HASH" do
      it_behaves_like "invalid format error", :hash, :standard_hash, :from_hash, :hash
    end
  end
end
