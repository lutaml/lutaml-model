# The vObject Serialization Format for Lutaml::Model
#
# This module provides support for serializing and deserializing models to/from
# vObject format, a text-based data format used by standards like vCard and iCalendar.
#
# == Basic Usage
#
# To use vObject serialization in your models:
#
#   class MyModel < Lutaml::Model::Serializable
#     attribute :field1, :string
#     attribute :field2, :string
#
#     vobject do
#       type :component          # Declare as component (like VCARD, VCALENDAR)
#       component_root "MYCOMP"  # Root component name
#
#       # Map vObject properties to model attributes
#       map_property "PROP1", to: :field1
#       map_property "PROP2", to: :field2
#     end
#   end
#
# == Creating Custom Components
#
# For non-standardized vObject components:
#
#   class MyCustomComponent < Lutaml::Model::Serializable
#     attribute :name, :string
#     attribute :details, MyCustomDetails
#
#     vobject do
#       type :component
#       component_root "X-CUSTOM"  # Use X- prefix for custom components
#
#       map_property "X-NAME", to: :name
#       map_property "X-DETAILS", to: :details, type: :structured
#     end
#   end
#
# == Custom Properties
#
# Define custom properties with parameters:
#
#   class MyCustomProperty < Lutaml::Model::Serializable
#     attribute :value, :string
#     attribute :param1, :string
#     attribute :param2, :integer
#
#     vobject do
#       type :property
#       property_name "X-CUSTOM-PROP"
#
#       map_value to: :value
#       map_property "PARAM1", to: :param1
#       map_property "PARAM2", to: :param2
#     end
#   end
#
# == Value Types
#
# Support for different value types:
#
# - Text (default)
# - URI
# - Binary (Base64)
# - Boolean
# - Integer
# - Float
# - UTC-Offset
# - Language-Tag
# - IsoDateAndOrTime
#
# == Custom Value Types
#
# Create custom value types by extending VobjectValueType::Base:
#
#   class MyCustomValue < VobjectValueType::Base
#     def valid?
#       # Add validation logic
#     end
#   end
#
# == Structured Values
#
# For properties with multiple fields:
#
#   vobject do
#     type :property
#     property_name "X-STRUCTURED"
#
#     map_field_set count: 3, item_type: :list
#     map_field 0, to: :first_field
#     map_field 1, to: :second_field
#     map_field 2, to: :third_field
#   end
#
# == Registration
#
# Register your custom format:
#
#   Lutaml::Model::Config.register_format(
#     :vobject,
#     mapping_class: YourMapping,
#     adapter_class: YourAdapter
#   )
#
# == Component Types
#
# Four types of elements are supported:
# - :component - Container components like VCARD
# - :property - Properties with values and parameters
# - :property_parameter - Parameters for properties
# - :property_group - Grouping of related properties
require "spec_helper"

module CustomVojectAdapterSpec
  class VobjectAdapter < Lutaml::Model::SerializationAdapter
    handles_format :vobject
    document_class Document
  end

  class VobjectDocument
    attr_reader :objects

    def initialize(objects = [])
      @objects = objects
    end

    def self.parse(vobject_data, _options = {})
      parser = Parser.new(vobject_data)
      new(parser.parse)
    end

    def to_vobject
      objects.map do |obj|
        [
          "BEGIN:#{obj.name}",
          *obj.properties.flat_map { |prop, entries| format_entries(prop, entries) },
          "END:#{obj.name}",
        ].join("\n")
      end.join("\n\n")
    end

    private

    def format_entries(prop, entries)
      entries.map do |entry|
        params = entry[:params].map { |k, v| "#{k}=#{v}" }.join(";")
        prop_line = params.empty? ? prop : "#{prop};#{params}"
        "#{prop_line}:#{entry[:value]}"
      end
    end
  end

  class VobjectParser
    def initialize(data)
      @data = data
      @current_object = nil
      @objects = []
    end

    def parse
      @data.each_line do |line|
        line.chomp!
        process_line(line)
      end
      @objects
    end

    private

    def process_line(line)
      case line
      when /^BEGIN:/
        @current_object = { name: line.split(":", 2).last, properties: {} }
      when /^END:/
        @objects << @current_object
        @current_object = nil
      else
        add_property(line) if @current_object
      end
    end

    def add_property(line)
      prop_part, value = line.split(":", 2)
      name, params = parse_property(prop_part)
      @current_object[:properties][name] ||= []
      @current_object[:properties][name] << { value: value, params: params }
    end

    def parse_property(prop_part)
      parts = prop_part.split(";")
      name = parts.shift.downcase
      params = parts.each_with_object({}) do |part, hash|
        k, v = part.split("=")
        hash[k.downcase] = v
      end
      [name, params]
    end
  end

  class VobjectMapping < Lutaml::Model::Mapping
    def initialize
      super
      @structure_definitions = {}
      @component_root = nil
      @property_root = nil
      @element_type = nil
    end

    def component_root(name)
      @component_root = name
    end

    def property_root(name)
      @property_root = name
    end

    def type(element_type)
      unless %i[component property property_parameter property_group].include?(element_type)
        raise ArgumentError, "Invalid element type: #{element_type}"
      end

      @element_type = element_type
    end

    def map_value(to:, **options)
      add_mapping(:value, to, type: :simple, **options)
    end

    def map_property(name, to:, type: :simple, **options)
      add_mapping(name.downcase, to, type: type, **options)
    end

    def map_component(name, to:, **options)
      add_mapping(name.downcase, to, type: :component, **options)
    end

    def map_field_set(count:, item_type:, item_options: {})
      @field_set = {
        count: count,
        item_type: item_type,
        options: item_options,
      }
    end

    def map_field(index, to:, **options)
      validate!(index, to, options)
      @mappings << FieldMappingRule.new(
        index,
        to: to,
        type: @field_set[:item_type],
        options: @field_set[:options].merge(options),
      )
    end

    private

    def add_mapping(name, to, **options)
      validate!(name, to, options)
      @mappings << VobjectMappingRule.new(
        name,
        to: to,
        type: options[:type],
        structure: @structure_definitions[to],
        options: options,
      )
    end
  end

  class VobjectMappingRule < Lutaml::Model::MappingRule
    attr_reader :structure, :type, :options

    def initialize(name, to:, type: :simple, structure: nil, options: {})
      super(name, to: to)
      @type = type
      @structure = structure
      @options = options
    end
  end

  class FieldMappingRule < VobjectMappingRule
    def initialize(index, to:, type:, options: {})
      super
    end
  end

  module ElementType
    COMPONENT = :component
    PROPERTY = :property
    PROPERTY_PARAMETER = :property_parameter
    PROPERTY_GROUP = :property_group
  end

  module ValueType
    PROPERTY_VALUE = :property_value
    PARAMETER_VALUE = :parameter_value
  end

  class Vcard < Lutaml::Model::Serializable
    attribute :version, :string
    attribute :fn, :string
    attribute :n, VcardName
    attribute :tel, VcardTel, collection: true
    attribute :email, :string, collection: true
    attribute :org, :string
    attribute :bday, VcardBday # Using the enhanced VcardBday class

    vobject do
      type :component
      component_root "VCARD"

      map_property "VERSION", to: :version
      map_property "FN", to: :fn
      map_property "N", to: :n, type: :structured
      map_property "TEL", to: :tel
      map_property "EMAIL", to: :email
      map_property "ORG", to: :org
      map_property "BDAY", to: :bday
    end

    Lutaml::Model::Config.register_format(
      :vobject,
      mapping_class: CustomBibtexAdapterSpec::VobjectMapping,
      adapter_class: CustomBibtexAdapterSpec::VobjectAdapter,
    )
  end

  module VobjectValueType
    class Base < Lutaml::Model::Value
      attr_accessor :element_type

      def initialize(value)
        super
        @element_type = :property_value
      end

      def as_property_value
        @element_type = :property_value
        self
      end

      def as_parameter_value
        @element_type = :parameter_value
        self
      end
    end

    class Text < Base
    end

    # URI as defined in Section 3 of [RFC3986]
    class Uri < Base
      def valid?
        uri = URI.parse(@value)
        !!(uri.scheme && uri.host)
      rescue URI::InvalidURIError
        false
      end
    end

    class Binary < Base
      def valid?
        Base64.strict_encode64(Base64.strict_decode64(@value)) == @value
      rescue ArgumentError
        false
      end
    end

    class IsoDateAndOrTime < Base
      attr_reader :type

      def initialize(value)
        super
        @type = detect_type(value)
      end

      private

      def detect_type(value)
        case value
        when /^\d{8}T\d{6}(Z|[+-]\d{4})?$/,
             /^--\d{4}T\d{4}$/,
             /^---\d{2}T\d{2}$/,
             /^T\d{6}(Z|[+-]\d{4})?$/,
             /^T\d{4}$/,
             /^T\d{2}$/,
             /^T-\d{4}$/,
             /^T--\d{2}$/
          :date_time
        when /^\d{8}$/,
             /^\d{6}$/,
             /^\d{4}$/,
             /^--\d{4}$/,
             /^---\d{2}$/
          :date
        else
          :text
        end
      end
    end

    class Boolean < Base
      VALID_VALUES = %w[TRUE FALSE true false].freeze

      def initialize(value)
        super(value.to_s.upcase)
      end

      def valid?
        VALID_VALUES.include?(@value)
      end

      def to_bool
        @value.upcase == "TRUE"
      end
    end

    class Integer < Lutaml::Model::Value::Integer
    end

    class Float < Lutaml::Model::Value::Float
    end

    class UtcOffset < Base
      def valid?
        @value.match?(/^[+-]\d{4}$/)
      end

      def hours
        @value[1..2].to_i * (@value[0] == "-" ? -1 : 1)
      end

      def minutes
        @value[3..4].to_i * (@value[0] == "-" ? -1 : 1)
      end
    end

    # Language-Tag as defined in [RFC5646]
    class Language < Base
      def valid?
        # Basic validation for language tags
        @value.match?(/^[a-zA-Z]{2,3}(-[a-zA-Z]{2,3})?$/)
      end
    end
  end

  class VcardBday < Lutaml::Model::Serializable
    attribute :value, VobjectValueType::IsoDateAndOrTime

    vobject do
      type :property
      property_name "BDAY"
      map_value to: :value
    end

    def value_type
      value.type
    end
  end

  class VcardTel < Lutaml::Model::Serializable
    attribute :value, :string
    attribute :type, :string
    attribute :pref, :integer

    vobject do
      type :property
      property_name "TEL"

      map_property "TYPE", to: :type
      map_property "PREF", to: :pref
      map_value to: :value
    end
  end

  class VcardName < Lutaml::Model::Serializable
    attribute :family, :string
    attribute :given, :string
    attribute :additional, :string
    attribute :prefix, :string
    attribute :suffix, :string

    vobject do
      type :property
      property_name "N"

      map_field_set(
        count: 5,
        item_type: :list,
        item_options: { type: :text },
      )
      map_field 0, to: :family
      map_field 1, to: :given
      map_field 2, to: :additional
      map_field 3, to: :prefix
      map_field 4, to: :suffix
    end
  end

  class VobjectPropertyValue
    def self.parse(value_str, value_type = nil, element_type = :property_value)
      unless %i[property_value parameter_value].include?(element_type)
        raise ArgumentError, "Invalid element type: #{element_type}"
      end

      value = case value_type&.upcase
              when "URI" then VobjectValueType::Uri.new(value_str)
              when "BINARY" then VobjectValueType::Binary.new(value_str)
              when "BOOLEAN" then VobjectValueType::Boolean.new(value_str)
              when "INTEGER" then VobjectValueType::Integer.new(value_str)
              when "FLOAT" then VobjectValueType::Float.new(value_str)
              when "UTC-OFFSET" then VobjectValueType::UtcOffset.new(value_str)
              when "LANGUAGE-TAG" then VobjectValueType::Language.new(value_str)
              when "DATE", "DATE-TIME", "DATE-AND-OR-TIME"
                VobjectValueType::IsoDateAndOrTime.new(value_str)
              else
                # Default to Text type for nil or "TEXT"
                VobjectValueType::Text.new(value_str)
              end

      value.element_type = element_type
      value
    end
  end

  RSpec.describe VobjectValueType do
    describe VobjectValueType::Text do
      it "handles text values" do
        text = described_class.new("Sample text")
        expect(text.to_s).to eq("Sample text")
      end
    end

    describe VobjectValueType::Uri do
      it "validates valid URIs" do
        uri = described_class.new("https://example.com")
        expect(uri).to be_valid
      end

      it "invalidates malformed URIs" do
        uri = described_class.new("not-a-uri")
        expect(uri).not_to be_valid
      end
    end

    describe VobjectValueType::Binary do
      it "validates base64 encoded data" do
        binary = described_class.new("SGVsbG8gV29ybGQ=") # "Hello World" in base64
        expect(binary).to be_valid
      end

      it "invalidates malformed base64 data" do
        binary = described_class.new("not-base64!")
        expect(binary).not_to be_valid
      end
    end

    describe VobjectValueType::Boolean do
      it "handles true values" do
        bool = described_class.new("TRUE")
        expect(bool).to be_valid
        expect(bool.to_bool).to be true
      end

      it "handles false values" do
        bool = described_class.new("false")
        expect(bool).to be_valid
        expect(bool.to_bool).to be false
      end

      it "invalidates non-boolean values" do
        bool = described_class.new("maybe")
        expect(bool).not_to be_valid
      end
    end

    describe VobjectValueType::Integer do
      it "validates integer values" do
        int = described_class.new("42")
        expect(int).to be_valid
        expect(int.to_i).to eq(42)
      end

      it "handles negative integers" do
        int = described_class.new("-42")
        expect(int).to be_valid
        expect(int.to_i).to eq(-42)
      end

      it "invalidates non-integer values" do
        int = described_class.new("4.2")
        expect(int).not_to be_valid
      end
    end

    describe VobjectValueType::Float do
      it "validates float values" do
        float = described_class.new("4.2")
        expect(float).to be_valid
        expect(float.to_f).to eq(4.2)
      end

      it "handles negative floats" do
        float = described_class.new("-4.2")
        expect(float).to be_valid
        expect(float.to_f).to eq(-4.2)
      end

      it "handles integer-like floats" do
        float = described_class.new("42")
        expect(float).to be_valid
        expect(float.to_f).to eq(42.0)
      end
    end

    describe VobjectValueType::UtcOffset do
      it "validates UTC offset format" do
        offset = described_class.new("+0200")
        expect(offset).to be_valid
        expect(offset.hours).to eq(2)
        expect(offset.minutes).to eq(0)
      end

      it "handles negative offsets" do
        offset = described_class.new("-0500")
        expect(offset).to be_valid
        expect(offset.hours).to eq(-5)
        expect(offset.minutes).to eq(0)
      end

      it "invalidates malformed offsets" do
        offset = described_class.new("0200")
        expect(offset).not_to be_valid
      end
    end

    describe VobjectValueType::Language do
      it "validates language tags" do
        lang = described_class.new("en-US")
        expect(lang).to be_valid
      end

      it "validates simple language codes" do
        lang = described_class.new("en")
        expect(lang).to be_valid
      end

      it "invalidates malformed language tags" do
        lang = described_class.new("not-a-language")
        expect(lang).not_to be_valid
      end
    end

    # ... existing IsoDateAndOrTime tests ...
  end

  RSpec.describe VobjectValueType::IsoDateAndOrTime do
    subject(:date_time) { described_class.new(value) }

    context "when parsing date-time values" do
      {
        "19961022T140000" => :date_time,
        "19961022T140000Z" => :date_time,
        "--1022T1400" => :date_time,
        "---22T14" => :date_time,
        "T102200" => :date_time,
        "T1022" => :date_time,
        "T10" => :date_time,
        "T-2200" => :date_time,
        "T--00" => :date_time,
        "T102200Z" => :date_time,
        "T102200-0800" => :date_time,
      }.each do |input, expected_type|
        context "with #{input}" do
          let(:value) { input }

          it "detects correct type" do
            expect(date_time.type).to eq(expected_type)
          end

          it "preserves original value" do
            expect(date_time.to_s).to eq(input)
          end
        end
      end
    end

    context "when parsing date values" do
      {
        "19850412" => :date,
        "1985-04" => :date,
        "1985" => :date,
        "--0412" => :date,
        "---12" => :date,
      }.each do |input, expected_type|
        context "with #{input}" do
          let(:value) { input }

          it "detects correct type" do
            expect(date_time.type).to eq(expected_type)
          end

          it "preserves original value" do
            expect(date_time.to_s).to eq(input)
          end
        end
      end
    end

    context "when parsing text values" do
      let(:value) { "Early April 1985" }

      it "detects as text type" do
        expect(date_time.type).to eq(:text)
      end

      it "preserves original value" do
        expect(date_time.to_s).to eq(value)
      end
    end
  end

  RSpec.describe VobjectPropertyValue do
    describe ".parse" do
      it "creates Text value by default" do
        value = described_class.parse("some text")
        expect(value).to be_a(VobjectValueType::Text)
      end

      it "creates URI value" do
        value = described_class.parse("https://example.com", "URI")
        expect(value).to be_a(VobjectValueType::Uri)
        expect(value).to be_valid
      end

      it "creates Binary value" do
        value = described_class.parse("SGVsbG8=", "BINARY")
        expect(value).to be_a(VobjectValueType::Binary)
        expect(value).to be_valid
      end

      it "creates Boolean value" do
        value = described_class.parse("TRUE", "BOOLEAN")
        expect(value).to be_a(VobjectValueType::Boolean)
        expect(value).to be_valid
        expect(value.to_bool).to be true
      end

      it "creates Integer value" do
        value = described_class.parse("42", "INTEGER")
        expect(value).to be_a(VobjectValueType::Integer)
        expect(value).to be_valid
        expect(value.to_i).to eq(42)
      end

      it "creates Float value" do
        value = described_class.parse("4.2", "FLOAT")
        expect(value).to be_a(VobjectValueType::Float)
        expect(value).to be_valid
        expect(value.to_f).to eq(4.2)
      end

      it "creates UTC-OFFSET value" do
        value = described_class.parse("+0200", "UTC-OFFSET")
        expect(value).to be_a(VobjectValueType::UtcOffset)
        expect(value).to be_valid
        expect(value.hours).to eq(2)
      end

      it "creates LANGUAGE-TAG value" do
        value = described_class.parse("en-US", "LANGUAGE-TAG")
        expect(value).to be_a(VobjectValueType::Language)
        expect(value).to be_valid
      end

      it "creates DATE-AND-OR-TIME value" do
        value = described_class.parse("19961022T140000", "DATE-AND-OR-TIME")
        expect(value).to be_a(VobjectValueType::IsoDateAndOrTime)
        expect(value.type).to eq(:date_time)
      end
    end
  end
end

RSpec.describe "Custom vObject adapter" do
  let(:full_vcard) do
    Vcard.new(
      version: "4.0",
      fn: "John Doe",
      n: VcardName.new(
        family: "Doe",
        given: "John",
        additional: "Middle",
        prefix: "Dr.",
        suffix: "PhD",
      ),
      tel: [
        VcardTel.new(number: "tel:+1-555-555-5555"),
        VcardTel.new(number: "tel:+1-555-555-1234"),
      ],
      email: ["john.doe@example.com", "j.doe@company.com"],
      org: "Example Corp",
      bday: VcardBday.new("1970-01-01"),
    )
  end

  let(:vobject_data) do
    <<~VCARD
      BEGIN:VCARD
      VERSION:4.0
      FN:John Doe
      N:Doe;John;Middle;Dr.;PhD
      TEL:tel:+1-555-555-5555
      TEL:tel:+1-555-555-1234
      EMAIL:john.doe@example.com
      EMAIL:j.doe@company.com
      ORG:Example Corp
      BDAY:1970-01-01
      END:VCARD
    VCARD
  end

  describe "#to_vobject" do
    it "serializes all fields correctly" do
      output = full_vcard.to_vobject.gsub(/\s+/, " ").strip
      expected = vobject_data.gsub(/\s+/, " ").strip

      expect(output).to eq(expected)
    end
  end

  describe ".from_vobject" do
    it "parses all fields correctly" do
      card = Vcard.from_vobject(vobject_data).first

      expect(card.version).to eq("4.0")
      expect(card.fn).to eq("John Doe")
      expect(card.n.family).to eq("Doe")
      expect(card.n.given).to eq("John")
      expect(card.n.additional).to eq("Middle")
      expect(card.n.prefix).to eq("Dr.")
      expect(card.n.suffix).to eq("PhD")
      expect(card.tel).to contain_exactly(
        "tel:+1-555-555-5555",
        "tel:+1-555-555-1234",
      )
      expect(card.email).to contain_exactly(
        "john.doe@example.com",
        "j.doe@company.com",
      )
      expect(card.org).to eq("Example Corp")
      expect(card.bday).to eq("1970-01-01")
    end
  end

  # Add test cases for different BDAY formats
  let(:iso_date_time_vcard) do
    <<~VCARD
      BEGIN:VCARD
      VERSION:4.0
      FN:John Doe
      BDAY:19961022T140000Z
      END:VCARD
    VCARD
  end

  let(:iso_date_vcard) do
    <<~VCARD
      BEGIN:VCARD
      VERSION:4.0
      FN:John Doe
      BDAY:19850412
      END:VCARD
    VCARD
  end

  let(:text_date_vcard) do
    <<~VCARD
      BEGIN:VCARD
      VERSION:4.0
      FN:John Doe
      BDAY:Early April 1985
      END:VCARD
    VCARD
  end

  describe ".from_vobject" do
    it "parses ISO date-time BDAY correctly" do
      card = Vcard.from_vobject(iso_date_time_vcard).first
      expect(card.bday.value.to_s).to eq("19961022T140000Z")
      expect(card.bday.type).to eq(:date_time)
    end

    it "parses ISO date BDAY correctly" do
      card = Vcard.from_vobject(iso_date_vcard).first
      expect(card.bday.value.to_s).to eq("19850412")
      expect(card.bday.type).to eq(:date)
    end

    it "parses text BDAY correctly" do
      card = Vcard.from_vobject(text_date_vcard).first
      expect(card.bday.value.to_s).to eq("Early April 1985")
      expect(card.bday.type).to eq(:text)
    end
  end
end

RSpec.describe VobjectMapping do
  let(:mapping) { described_class.new }

  describe "#type" do
    it "accepts valid element types" do
      expect { mapping.type(:component) }.not_to raise_error
      expect { mapping.type(:property) }.not_to raise_error
      expect { mapping.type(:property_parameter) }.not_to raise_error
      expect { mapping.type(:property_group) }.not_to raise_error
    end

    it "rejects invalid element types" do
      expect { mapping.type(:invalid) }.to raise_error(ArgumentError)
    end
  end

  describe "#component_root" do
    it "sets the component root" do
      mapping.component_root("VCARD")
      expect(mapping.instance_variable_get(:@component_root)).to eq("VCARD")
    end
  end

  describe "#property_root" do
    it "sets the property root" do
      mapping.property_root("TEL")
      expect(mapping.instance_variable_get(:@property_root)).to eq("TEL")
    end
  end

  describe "#map_field_set and #map_field" do
    it "maps fields correctly" do
      mapping.map_field_set(
        count: 3,
        item_type: :list,
        item_options: { type: :text },
      )

      mapping.map_field(0, to: :first)
      mapping.map_field(1, to: :second)
      mapping.map_field(2, to: :third)

      mappings = mapping.instance_variable_get(:@mappings)
      expect(mappings.size).to eq(3)
      expect(mappings[0].name).to eq(0)
      expect(mappings[0].to).to eq(:first)
      expect(mappings[0].type).to eq(:list)
    end
  end
end

RSpec.describe VobjectPropertyValue do
  describe ".parse" do
    it "sets element type correctly" do
      value = described_class.parse("test", "TEXT", :property_value)
      expect(value.element_type).to eq(:property_value)

      value = described_class.parse("test", "TEXT", :parameter_value)
      expect(value.element_type).to eq(:parameter_value)
    end

    it "rejects invalid element types" do
      expect do
        described_class.parse("test", "TEXT", :invalid)
      end.to raise_error(ArgumentError)
    end
  end
end

RSpec.describe VobjectValueType::Base do
  let(:value) { described_class.new("test") }

  describe "#as_property_value" do
    it "changes element type to property_value" do
      value.as_parameter_value
      value.as_property_value
      expect(value.element_type).to eq(:property_value)
    end
  end

  describe "#as_parameter_value" do
    it "changes element type to parameter_value" do
      value.as_parameter_value
      expect(value.element_type).to eq(:parameter_value)
    end
  end
end
