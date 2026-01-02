# spec/lutaml/model/type_spec.rb
require "spec_helper"
require "bigdecimal"

class CustomSerializationType < Lutaml::Model::Type::Value
  def self.from_xml(_xml_string)
    "from_xml_overrided"
  end

  def self.from_json(_value)
    "from_json_overrided"
  end

  def self.serialize(_value)
    "serialize_overrided"
  end

  def to_xml
    "to_xml_overrided"
  end

  def to_json(*_args)
    "to_json_overrided"
  end
end

class SampleModel < Lutaml::Model::Serializable
  attribute :custom_type, CustomSerializationType
  xml do
    root "sample"
    map_element "custom_type", to: :custom_type
  end
  json do
    map_element "custom_type", to: :custom_type
  end
end

class SampleModelAttribute < Lutaml::Model::Serializable
  attribute :custom_type, CustomSerializationType
  xml do
    root "sample"
    map_attribute "custom_type", to: :custom_type
  end
  json do
    map_element "custom_type", to: :custom_type
  end
end

RSpec.describe Lutaml::Model::Type do
  describe "Type System" do
    describe ".register and .lookup" do
      context "with valid types" do
        before do
          # Test class for type registration scenarios
          custom_type = Class.new(Lutaml::Model::Type::Value) do
            def self.cast(value)
              value.to_s.upcase
            end
          end

          stub_const("CustomType", custom_type)
        end

        it "registers and looks up a custom type" do
          described_class.register(:custom, CustomType)
          expect(described_class.lookup(:custom)).to eq(CustomType)
        end

        it "allows overriding an existing type registration" do
          described_class.register(:custom, CustomType)
          replacement_type = Class.new(Lutaml::Model::Type::Value)
          described_class.register(:custom, replacement_type)
          expect(described_class.lookup(:custom)).to eq(replacement_type)
        end
      end

      context "with invalid types" do
        before do
          invalid_type = Class.new do
            def self.cast(value)
              value
            end
          end

          stub_const("InvalidType", invalid_type)
        end

        it "raises TypeError when registering non-Type::Value class" do
          expect do
            described_class.register(:invalid,
                                     InvalidType)
          end.to raise_error(Lutaml::Model::TypeError,
                             /not a valid Lutaml::Model::Type::Value/)
        end

        it "raises UnknownTypeError when looking up unregistered type" do
          expect do
            described_class.lookup(:nonexistent)
          end.to raise_error(
            Lutaml::Model::UnknownTypeError, /Unknown type 'nonexistent'/
          )
        end
      end
    end

    describe "Built-in Types" do
      before do
        described_class.register_builtin_types
      end

      after do
        described_class.instance_variable_set(:@registry, nil)
      end

      let(:built_in_types) do
        {
          string: Lutaml::Model::Type::String,
          integer: Lutaml::Model::Type::Integer,
          float: Lutaml::Model::Type::Float,
          date: Lutaml::Model::Type::Date,
          time: Lutaml::Model::Type::Time,
          date_time: Lutaml::Model::Type::DateTime,
          time_without_date: Lutaml::Model::Type::TimeWithoutDate,
          boolean: Lutaml::Model::Type::Boolean,
          hash: Lutaml::Model::Type::Hash,
        }
      end

      it "has all built-in types registered" do
        built_in_types.each do |type_name, type_class|
          puts described_class
          expect(described_class.lookup(type_name)).to eq(type_class)
        end
      end

      describe "Type Casting" do
        let(:test_date) { Date.new(2024, 1, 1) }
        let(:test_time) { Time.new(2024, 1, 1, 12, 0, 0) }
        let(:test_date_time) { DateTime.new(2024, 1, 1, 12, 0, 0) }

        {
          Lutaml::Model::Type::String => { input: 123, expected: "123" },
          Lutaml::Model::Type::Integer => { input: "123", expected: 123 },
          Lutaml::Model::Type::Float => { input: "123.45", expected: 123.45 },
          Lutaml::Model::Type::Date => { input: "2024-01-01",
                                         expected: Date.new(2024, 1, 1) },
          Lutaml::Model::Type::Time => { input: "2024-01-01T12:00:00",
                                         expected_hour: 12 },
          Lutaml::Model::Type::DateTime => { input: "2024-01-01T12:00:00",
                                             expected: DateTime.new(2024, 1, 1,
                                                                    12, 0, 0) },
          Lutaml::Model::Type::Boolean => { input: "true", expected: true },
          Lutaml::Model::Type::Hash => { input: { key: "value" },
                                         expected: { key: "value" } },
        }.each do |type_class, test_data|
          it "correctly casts #{type_class}" do
            result = type_class.cast(test_data[:input])
            if test_data.key?(:expected_hour)
              expect(result.hour).to eq(test_data[:expected_hour])
            else
              expect(result).to eq(test_data[:expected])
            end
          end
        end

        it "handles nil values gracefully" do
          built_in_types.each_value do |type_class|
            expect(type_class.cast(nil)).to be_nil
          end
        end
      end
    end

    describe "Decimal Type" do
      context "when BigDecimal is available" do
        before do
          require "bigdecimal"
          described_class.register_builtin_types
        end

        it "registers and uses Decimal type" do
          expect(described_class.lookup(:decimal)).to eq(Lutaml::Model::Type::Decimal)
          expect(Lutaml::Model::Type::Decimal.cast("123.45")).to eq(BigDecimal("123.45"))
        end

        it "serializes decimal values correctly" do
          value = BigDecimal("123.45")
          expect(Lutaml::Model::Type::Decimal.serialize(value)).to eq("123.45")
        end
      end

      context "when BigDecimal is not available" do
        before do
          hide_const("BigDecimal") if defined?(BigDecimal)
        end

        let(:decimal_class) { described_class.lookup(:decimal) }

        it "raises TypeNotEnabledError when using Decimal type" do
          expect do
            decimal_class.cast("123.45")
          end.to raise_error(Lutaml::Model::TypeNotEnabledError)
        end
      end
    end
  end

  describe "Type Usage in Models" do
    before do
      type_test_model = Class.new(Lutaml::Model::Serializable) do
        attribute :string_symbol, :string
        attribute :string_class, Lutaml::Model::Type::String
        attribute :integer_value, :integer
        attribute :float_value, :float
        attribute :date_value, :date
        attribute :time_value, :time
        attribute :time_without_date_value, :time_without_date
        attribute :date_time_value, :date_time
        attribute :boolean_value, :boolean
        attribute :hash_value, :hash

        xml do
          root "test"
          map_element "string_symbol", to: :string_symbol
          map_element "string_class", to: :string_class
          map_element "integer", to: :integer_value
          map_element "float", to: :float_value
          map_element "date", to: :date_value
          map_element "time", to: :time_value
          map_element "time_without_date", to: :time_without_date_value
          map_element "date_time", to: :date_time_value
          map_element "boolean", to: :boolean_value
          map_element "hash", to: :hash_value
        end
      end

      stub_const("TypeTestModel", type_test_model)
    end

    let(:test_instance) do
      TypeTestModel.new(
        string_symbol: "test",
        string_class: "test",
        integer_value: "123",
        float_value: "123.45",
        date_value: "2024-01-01",
        time_value: "12:00:00",
        time_without_date_value: "10:06:15",
        date_time_value: "2024-01-01T12:00:00",
        boolean_value: "true",
        hash_value: { key: "value" },
      )
    end

    describe "Type Casting in Models" do
      it "correctly casts values using both symbol and class-based types" do
        expect(test_instance.string_symbol).to eq("test")
        expect(test_instance.string_class).to eq("test")
        expect(test_instance.integer_value).to eq(123)
        expect(test_instance.float_value).to eq(123.45)
        expect(test_instance.date_value).to eq(Date.new(2024, 1, 1))
        expect(test_instance.time_value.hour).to eq(12)
        expect(test_instance.date_time_value).to eq(DateTime.new(2024, 1, 1,
                                                                 12, 0, 0))
        expect(test_instance.boolean_value).to be(true)
        expect(test_instance.hash_value).to eq({ key: "value" })
      end

      it "produces identical results with symbol and class-based definitions" do
        expect(test_instance.string_symbol).to eq(test_instance.string_class)
      end
    end

    describe "Serialization" do
      let(:xml) do
        <<~XML
          <test>
            <string_symbol>test</string_symbol>
            <string_class>test</string_class>
            <integer>123</integer>
            <float>123.45</float>
            <date>2024-01-01</date>
            <time>#{Time.parse('12:00:00').iso8601}</time>
            <time_without_date>10:06:15</time_without_date>
            <date_time>2024-01-01T12:00:00Z</date_time>
            <boolean>true</boolean>
            <hash>
              <key>value</key>
            </hash>
          </test>
        XML
      end

      it "correctly serializes to XML" do
        expect(test_instance.to_xml).to be_xml_equivalent_to(xml)
      end

      it "correctly deserializes from XML" do
        deserialized = TypeTestModel.from_xml(xml)
        expect(deserialized.string_symbol).to eq("test")
        expect(deserialized.string_class).to eq("test")
        expect(deserialized.integer_value).to eq(123)
        expect(deserialized.float_value).to eq(123.45)
        expect(deserialized.date_value).to eq(Date.new(2024, 1, 1))
        expect(deserialized.date_time_value).to eq(DateTime.new(2024, 1, 1, 12,
                                                                0, 0))
        expect(deserialized.boolean_value).to be(true)
        expect(deserialized.hash_value).to eq({ "key" => "value" })
      end
    end

    describe "Serialization Of Custom Type" do
      let(:xml) do
        <<~XML
          <sample>
            <custom_type>test_string</custom_type>
          </sample>
        XML
      end

      let(:xml_attribute) do
        <<~XML
          <sample custom_type="test_string"/>
        XML
      end

      let(:sample_instance) { SampleModel.from_xml(xml) }
      let(:sample_instance_attribute) do
        SampleModelAttribute.from_xml(xml_attribute)
      end

      it "correctly serializes to XML" do
        expected_xml = <<~XML
          <sample>
            <custom_type>to_xml_overrided</custom_type>
          </sample>
        XML
        expect(sample_instance.to_xml).to be_xml_equivalent_to(expected_xml)
      end

      it "correctly serializes to XML attribute" do
        expected_xml = <<~XML
          <sample custom_type="to_xml_overrided"/>
        XML
        expect(
          sample_instance_attribute.to_xml,
        ).to be_xml_equivalent_to(expected_xml)
      end

      it "correctly serializes to JSON" do
        expected_value = '{"custom_type":"to_json_overrided"}'
        expect(sample_instance.to_json).to eq(expected_value)
      end

      it "correctly deserializes from XML" do
        expect(sample_instance.custom_type).to eq("from_xml_overrided")
      end

      it "correctly deserializes from JSON" do
        json_input = '{"custom_type":"test_string"}'
        json_sample_instance = SampleModel.from_json(json_input)
        json_sample_instance.to_json
        expect(json_sample_instance.custom_type).to eq("from_json_overrided")
      end
    end
  end
end
