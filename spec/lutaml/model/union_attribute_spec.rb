# frozen_string_literal: true

require "spec_helper"

# Behavioral contract for issue #190 union-typed attributes:
#   - DSL: bare Array in type position  ->  attribute :x, [A, B, :string]
#   - Semantics: xsd:union  ->  first-conforming member in declared order wins;
#     valid if it conforms to at least one member (NO "exactly one" rule).
#   - No-match: a real value matching no member becomes nil (like every failed
#     cast); `required: true` then raises the standard RequiredAttributeMissingError.
#   - Stateless serialization: the value's own class drives output, so a model
#     built in plain Ruby serializes identically to a deserialized one.
module UnionAttributeSpec
  # Type-only member (no root declared) — structured, keys {number, unit}.
  class TemperatureWithUnit < Lutaml::Model::Serializable
    attribute :number, :float
    attribute :unit, :string

    xml do
      map_element "number", to: :number
      map_element "unit", to: :unit
    end

    key_value do
      map "number", to: :number
      map "unit", to: :unit
    end
  end

  # Type-only member — structured, disjoint key {celsius}.
  class Temperature < Lutaml::Model::Serializable
    attribute :celsius, :float

    xml do
      map_element "celsius", to: :celsius
    end

    key_value do
      map "celsius", to: :celsius
    end
  end

  # Mixed scalar + model union under a single shared element name.
  class Ceramic < Lutaml::Model::Serializable
    attribute :firing_temperature,
              [TemperatureWithUnit, Temperature, :string]

    xml do
      element "ceramic"
      map_element "FiringTemperature", to: :firing_temperature
    end

    key_value do
      map "firing_temperature", to: :firing_temperature
    end
  end

  # Scalar union with a catch-all — exercises first-conforming order.
  class Reading < Lutaml::Model::Serializable
    attribute :value, %i[integer string]

    key_value do
      map "value", to: :value
    end
  end

  # Model member whose mapping aliases one attribute to two keys.
  class AliasedMember < Lutaml::Model::Serializable
    attribute :name, :string

    key_value do
      map %w[name product_name], to: :name
    end
  end

  # Union holding the aliased member (plus a scalar catch-all).
  class AliasedHolder < Lutaml::Model::Serializable
    attribute :value, [AliasedMember, :string]

    key_value do
      map "value", to: :value
    end
  end

  # Scalar union carrying enum + default constraints, for JSON Schema.
  class ConstrainedReading < Lutaml::Model::Serializable
    attribute :value, %i[integer string], values: [1, "one"], default: "one"

    key_value do
      map "value", to: :value
    end
  end

  # Union with a :string member carrying a pattern — the pattern binds the
  # string branch; a model member value is exempt.
  class PatternedHolder < Lutaml::Model::Serializable
    attribute :code, [Temperature, :string], pattern: /\A[A-Z]+\z/

    key_value do
      map "code", to: :code
    end
  end

  # Union collection carrying a pattern — each string element is checked;
  # non-string (integer) elements are exempt.
  class PatternedList < Lutaml::Model::Serializable
    attribute :codes, %i[integer string], collection: true,
                                          pattern: /\A[A-Z]+\z/

    key_value do
      map "codes", to: :codes
    end
  end

  # Scalar union, no catch-all — no-match yields nil (library default).
  class OptionalReading < Lutaml::Model::Serializable
    attribute :value, %i[integer float]

    key_value do
      map "value", to: :value
    end
  end

  # Same, but required — no-match -> nil -> standard RequiredAttributeMissingError.
  class RequiredReading < Lutaml::Model::Serializable
    attribute :value, %i[integer float], required: true

    key_value do
      map "value", to: :value
    end
  end

  # Collection of union values (heterogeneous).
  class ReadingSet < Lutaml::Model::Serializable
    attribute :readings,
              [TemperatureWithUnit, :string], collection: true

    key_value do
      map "readings", to: :readings
    end
  end

  # Scalar union collection — for JSON Schema array-wrapping.
  class IntStringList < Lutaml::Model::Serializable
    attribute :vals, %i[integer string], collection: true

    key_value do
      map "vals", to: :vals
    end
  end

  # :decimal member — native BigDecimal + decimal string.
  class DecimalReading < Lutaml::Model::Serializable
    attribute :value, %i[decimal string]

    key_value do
      map "value", to: :value
    end
  end

  # Simple-content model (text content + attribute) union member.
  class Amount < Lutaml::Model::Serializable
    attribute :value, :string
    attribute :unit, :string

    xml do
      map_content to: :value
      map_attribute "unit", to: :unit
    end

    key_value do
      map "value", to: :value
      map "unit", to: :unit
    end
  end

  class Measurement < Lutaml::Model::Serializable
    attribute :amount, [Amount, :string]

    xml do
      element "measurement"
      map_element "amount", to: :amount
    end
  end

  # Class-based transformer that builds the union's model member itself —
  # key_value transforms apply `transform:` BEFORE the cast, so the cast
  # receives an already-constructed member instance.
  class TemperatureTransformer < Lutaml::Model::ValueTransformer
    def from_yaml(value)
      return value unless value.is_a?(::Hash)

      TemperatureWithUnit.new(value.transform_keys(&:to_sym))
    end
  end

  class TransformedReading < Lutaml::Model::Serializable
    attribute :temp, [TemperatureWithUnit, :string]

    key_value do
      map "temp", to: :temp, transform: TemperatureTransformer
    end
  end

  # XML collection mixing structured members and castable scalar text.
  class TemperatureLog < Lutaml::Model::Serializable
    attribute :entries, [TemperatureWithUnit, :integer],
              collection: true

    xml do
      element "log"
      map_element "entry", to: :entries
    end
  end
end

RSpec.describe "Union-typed attributes (issue #190)" do
  describe "deserialization — member resolution by shape" do
    it "resolves a scalar string to the :string member" do
      ceramic = UnionAttributeSpec::Ceramic.from_yaml(
        "firing_temperature: Very Hot",
      )
      expect(ceramic.firing_temperature).to eq("Very Hot")
    end

    it "resolves a structured value to the covering model member (number+unit)" do
      ceramic = UnionAttributeSpec::Ceramic.from_yaml(<<~YAML)
        firing_temperature:
          number: 1300.0
          unit: C
      YAML
      expect(ceramic.firing_temperature)
        .to be_a(UnionAttributeSpec::TemperatureWithUnit)
      expect(ceramic.firing_temperature.number).to eq(1300.0)
      expect(ceramic.firing_temperature.unit).to eq("C")
    end

    it "resolves a text-only XML element with an unrelated attribute to the string member" do
      ceramic = UnionAttributeSpec::Ceramic.from_xml(
        '<ceramic><FiringTemperature lang="en">Very Hot</FiringTemperature></ceramic>',
      )
      expect(ceramic.firing_temperature).to eq("Very Hot")
    end

    it "resolves a simple-content (map_content + map_attribute) model member in XML" do
      m = UnionAttributeSpec::Measurement.from_xml(
        '<measurement><amount unit="kg">5</amount></measurement>',
      )
      expect(m.amount).to be_a(UnionAttributeSpec::Amount)
      expect(m.amount.value).to eq("5")
      expect(m.amount.unit).to eq("kg")
    end

    it "resolves a structured value with a disjoint key to the other model member" do
      ceramic = UnionAttributeSpec::Ceramic.from_yaml(<<~YAML)
        firing_temperature:
          celsius: 1200.0
      YAML
      expect(ceramic.firing_temperature)
        .to be_a(UnionAttributeSpec::Temperature)
      expect(ceramic.firing_temperature.celsius).to eq(1200.0)
    end
  end

  describe "round-trip fidelity (deserialized)" do
    %i[yaml json].each do |format|
      it "round-trips the scalar case through #{format}" do
        ceramic = UnionAttributeSpec::Ceramic.from_yaml(
          "firing_temperature: Very Hot",
        )
        reparsed = UnionAttributeSpec::Ceramic.public_send(
          :"from_#{format}", ceramic.public_send(:"to_#{format}")
        )
        expect(reparsed.firing_temperature).to eq("Very Hot")
      end

      it "round-trips the structured case through #{format}" do
        ceramic = UnionAttributeSpec::Ceramic.from_yaml(<<~YAML)
          firing_temperature:
            number: 1300.0
            unit: C
        YAML
        reparsed = UnionAttributeSpec::Ceramic.public_send(
          :"from_#{format}", ceramic.public_send(:"to_#{format}")
        )
        expect(reparsed.firing_temperature)
          .to be_a(UnionAttributeSpec::TemperatureWithUnit)
        expect(reparsed.firing_temperature.number).to eq(1300.0)
      end
    end

    it "round-trips both XML cases (text-only vs child elements)" do
      scalar = UnionAttributeSpec::Ceramic.from_xml(
        "<ceramic><FiringTemperature>Very Hot</FiringTemperature></ceramic>",
      )
      expect(scalar.firing_temperature).to eq("Very Hot")
      expect(UnionAttributeSpec::Ceramic.from_xml(scalar.to_xml)
        .firing_temperature).to eq("Very Hot")

      structured = UnionAttributeSpec::Ceramic.from_xml(<<~XML)
        <ceramic><FiringTemperature><number>1300.0</number><unit>C</unit></FiringTemperature></ceramic>
      XML
      expect(structured.firing_temperature)
        .to be_a(UnionAttributeSpec::TemperatureWithUnit)
      reparsed = UnionAttributeSpec::Ceramic.from_xml(structured.to_xml)
      expect(reparsed.firing_temperature.unit).to eq("C")
    end
  end

  describe "plain-Ruby construction (stateless serialization — the v1 bug class)" do
    it "serializes a model member built in plain Ruby identically to a deserialized one" do
      built = UnionAttributeSpec::Ceramic.new(
        firing_temperature:
          UnionAttributeSpec::TemperatureWithUnit.new(number: 1300.0, unit: "C"),
      )
      round = UnionAttributeSpec::Ceramic.from_yaml(built.to_yaml)
      expect(round.firing_temperature)
        .to be_a(UnionAttributeSpec::TemperatureWithUnit)
      expect(round.firing_temperature.number).to eq(1300.0)
    end

    it "does NOT double-encode a plain-Ruby scalar member" do
      built = UnionAttributeSpec::Ceramic.new(firing_temperature: "Very Hot")
      expect(JSON.parse(built.to_json)["firing_temperature"]).to eq("Very Hot")
    end

    it "does not raise serializing a plain-Ruby scalar to TOML" do
      built = UnionAttributeSpec::Ceramic.new(firing_temperature: "Very Hot")
      expect { built.to_toml }.not_to raise_error
    end

    it "builds a model member from a plain-Ruby hash (attribute-name keys)" do
      built = UnionAttributeSpec::Ceramic.new(
        firing_temperature: { number: 1300.0, unit: "C" },
      )
      expect(built.firing_temperature)
        .to be_a(UnionAttributeSpec::TemperatureWithUnit)
      expect(built.firing_temperature.number).to eq(1300.0)
    end
  end

  describe "first-conforming-in-declared-order (xsd:union)" do
    it "prefers the earlier member when several could match" do
      # "42" conforms to Integer's lexical space, so Integer wins over :string.
      expect(UnionAttributeSpec::Reading.from_yaml("value: '42'").value).to eq(42)
    end

    it "falls through to the catch-all when earlier members reject the value" do
      expect(UnionAttributeSpec::Reading.from_yaml("value: hello").value)
        .to eq("hello")
    end
  end

  describe "no-match handling (lenient by default, like every cast)" do
    it "yields nil when no member conforms" do
      reading = UnionAttributeSpec::OptionalReading.new(value: "not a number")
      expect(reading.value).to be_nil
    end

    it "raises the standard RequiredAttributeMissingError when required and nothing conforms" do
      reading = UnionAttributeSpec::RequiredReading.new(value: "not a number")
      # `validate!` aggregates per-attribute errors into a ValidationError (the
      # library's universal contract for every required attribute, union or not);
      # the underlying error is the standard RequiredAttributeMissingError.
      expect { reading.validate! }.to raise_error(
        Lutaml::Model::ValidationError,
      ) { |error| expect(error).to include(Lutaml::Model::RequiredAttributeMissingError) }
    end

    it "never trips on nil" do
      expect { UnionAttributeSpec::OptionalReading.new(value: nil) }
        .not_to raise_error
    end
  end

  describe "definition-time member validation" do
    it "raises on an empty member list (attribute :x, [])" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :empty_union, []
        end
      end.to raise_error(ArgumentError)
    end

    it "raises when the array contains no valid member type" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :bad_union, [Object]
        end
      end.to raise_error(ArgumentError)
    end

    it "raises when ANY member is invalid (not only when all are)" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :mixed_union, [UnionAttributeSpec::Temperature, Object]
        end
      end.to raise_error(ArgumentError)
    end

    it "raises when a catch-all :string is not the last union member" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :bad_order, %i[string integer]
        end
      end.to raise_error(ArgumentError)
    end

    it "raises when a catch-all :string precedes a model member" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :bad_order,
                    [:string, UnionAttributeSpec::Temperature]
        end
      end.to raise_error(ArgumentError, /last union member/)
    end

    it "raises clearly when a member is an option hash (e.g. { ref: ... })" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :ref_union, [{ ref: %w[Target id] }, :string]
        end
      end.to raise_error(ArgumentError, /not supported as union members/)
    end

    it "rejects unsupported scalar member types at definition time" do
      %i[hash symbol time time_without_date date date_time].each do |unsupported|
        expect do
          Class.new(Lutaml::Model::Serializable) do
            attribute :bad, [unsupported, :string]
          end
        end.to raise_error(ArgumentError, /unsupported union member/),
               "expected #{unsupported.inspect} to be rejected"
      end
    end
  end

  describe "decimal and numeric scalar members" do
    it "accepts a native BigDecimal for a :decimal member" do
      require "bigdecimal"
      reading = UnionAttributeSpec::DecimalReading.new(value: BigDecimal("1.5"))
      expect(reading.value).to eq(BigDecimal("1.5"))
    end

    it "resolves a decimal string to the :decimal member" do
      reading = UnionAttributeSpec::DecimalReading.from_yaml("value: '1.5'")
      expect(reading.value).to eq(BigDecimal("1.5"))
    end

    it "serializes a scalar decimal through its type, not as a raw Ruby object" do
      yaml = UnionAttributeSpec::DecimalReading.new(value: BigDecimal("1.5")).to_yaml
      expect(yaml).not_to include("ruby/object")
      expect(UnionAttributeSpec::DecimalReading.from_yaml(yaml).value)
        .to eq(BigDecimal("1.5"))
    end

    it "resolves XSD-style boolean literals (1/yes) to :boolean, else :string" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, %i[boolean string]
        key_value { map "value", to: :value }
      end
      expect(klass.from_yaml("value: '1'").value).to be(true)
      expect(klass.from_yaml("value: 'maybe'").value).to eq("maybe")
    end

    it "accepts a native Integer for a :float member (lossless widening)" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, %i[float string]
        key_value { map "value", to: :value }
      end
      value = klass.new(value: 42).value
      expect(value).to be_a(Float)
      expect(value).to eq(42.0)
    end

    it "accepts a native Integer for a :decimal member" do
      require "bigdecimal"
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, %i[decimal string]
        key_value { map "value", to: :value }
      end
      expect(klass.new(value: 42).value).to eq(BigDecimal(42))
    end

    it "rejects a lossy native numeric for :integer (3.7 falls through to :float)" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, %i[integer float]
        key_value { map "value", to: :value }
      end
      value = klass.new(value: 3.7).value
      expect(value).to be_a(Float)
      expect(value).to eq(3.7)
    end

    it "keeps a whole-valued native Float a Float for :integer (3.0 stays 3.0)" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :value, %i[integer float]
        key_value { map "value", to: :value }
      end
      obj = klass.new(value: 3.0)
      expect(obj.value).to be_a(Float)
      expect(obj.value).to eq(3.0)
      expect(obj.to_json).to eq('{"value":3.0}')
    end
  end

  describe "JSON Schema export" do
    it "wraps a collection union as an array of anyOf" do
      attr = UnionAttributeSpec::IntStringList.attributes[:vals]
      schema = Lutaml::Model::Schema::Generator::Property.new(
        :vals, attr, register: Lutaml::Model::Config.default_register
      ).to_schema
      expect(schema["vals"]["type"]).to eq("array")
      expect(schema["vals"]["items"]).to have_key("anyOf")
    end

    it "exports an optional scalar union as anyOf including a null branch" do
      attr = UnionAttributeSpec::Reading.attributes[:value]
      schema = Lutaml::Model::Schema::Generator::Property.new(
        :value, attr, register: Lutaml::Model::Config.default_register
      ).to_schema
      expect(schema["value"]).to have_key("anyOf")
      expect(schema["value"]["anyOf"]).to include("type" => "null")
    end

    it "includes $defs entries for a union's model members (no dangling $ref)" do
      schema = JSON.parse(
        Lutaml::Model::Schema::JsonSchema.generate(UnionAttributeSpec::Ceramic),
      )
      defs = schema["$defs"] || schema["definitions"] || {}
      refs = JSON.generate(schema)
        .scan(%r{#/(?:\$defs|definitions)/([^"]+)}).flatten
      expect(refs).not_to be_empty
      expect(refs - defs.keys).to be_empty
    end

    it "carries enum and default constraints onto a union schema" do
      attr = UnionAttributeSpec::ConstrainedReading.attributes[:value]
      schema = Lutaml::Model::Schema::Generator::Property.new(
        :value, attr, register: Lutaml::Model::Config.default_register
      ).to_schema
      expect(schema["value"]).to have_key("anyOf")
      expect(schema["value"]["enum"]).to eq([1, "one"])
      expect(schema["value"]["default"]).to eq("one")
    end

    # A :decimal (BigDecimal) serializes to JSON as a string (to preserve
    # arbitrary precision), so its union schema branch is "string" — matching
    # the actual output rather than the README's number classification.
    it "maps a decimal union member to a string branch matching its output" do
      attr = UnionAttributeSpec::DecimalReading.attributes[:value]
      schema = Lutaml::Model::Schema::Generator::Property.new(
        :value, attr, register: Lutaml::Model::Config.default_register
      ).to_schema
      types = schema["value"]["anyOf"].map { |member| member["type"] }
      expect(types).to include("string")
      json = UnionAttributeSpec::DecimalReading.new(value: BigDecimal("1.5"))
        .to_json
      expect(JSON.parse(json)["value"]).to be_a(String)
    end
  end

  describe "pattern on a union with a :string member" do
    it "accepts a string value matching the pattern" do
      expect(UnionAttributeSpec::PatternedHolder.new(code: "ABC")
        .validate).to be_empty
    end

    it "rejects a string value violating the pattern" do
      expect(UnionAttributeSpec::PatternedHolder.new(code: "ab1")
        .validate).not_to be_empty
    end

    it "exempts a non-string member value from the pattern" do
      temp = UnionAttributeSpec::Temperature.new(celsius: 12.0)
      expect(UnionAttributeSpec::PatternedHolder.new(code: temp)
        .validate).to be_empty
    end

    it "checks each string element of a union collection" do
      expect(UnionAttributeSpec::PatternedList.new(codes: %w[ABC DEF])
        .validate).to be_empty
      expect(UnionAttributeSpec::PatternedList.new(codes: ["ABC", "bad"])
        .validate).not_to be_empty
    end

    it "exempts non-string elements of a union collection" do
      expect(UnionAttributeSpec::PatternedList.new(codes: [1, "ABC"])
        .validate).to be_empty
      expect(UnionAttributeSpec::PatternedList.new(codes: [1, "bad"])
        .validate).not_to be_empty
    end
  end

  describe "model member with aliased serialization keys" do
    it "resolves the member through its aliased key" do
      holder = UnionAttributeSpec::AliasedHolder.from_yaml(<<~YAML)
        value:
          product_name: Vase
      YAML
      expect(holder.value).to be_a(UnionAttributeSpec::AliasedMember)
      expect(holder.value.name).to eq("Vase")
    end

    it "resolves the member through its primary key" do
      holder = UnionAttributeSpec::AliasedHolder.from_yaml(<<~YAML)
        value:
          name: Vase
      YAML
      expect(holder.value).to be_a(UnionAttributeSpec::AliasedMember)
      expect(holder.value.name).to eq("Vase")
    end
  end

  describe "collections of union values" do
    it "resolves each element independently (mixed model + scalar)" do
      set = UnionAttributeSpec::ReadingSet.from_yaml(<<~YAML)
        readings:
          - number: 1300.0
            unit: C
          - Very Hot
      YAML
      expect(set.readings.first)
        .to be_a(UnionAttributeSpec::TemperatureWithUnit)
      expect(set.readings.last).to eq("Very Hot")
    end

    it "casts scalar elements in an XML collection mixing model members" do
      log = UnionAttributeSpec::TemperatureLog.from_xml(<<~XML)
        <log>
          <entry>42</entry>
          <entry><number>1300.0</number><unit>C</unit></entry>
          <entry>7</entry>
        </log>
      XML
      expect(log.entries.map(&:class))
        .to eq([Integer, UnionAttributeSpec::TemperatureWithUnit, Integer])
      expect(log.entries.first).to eq(42)

      reparsed = UnionAttributeSpec::TemperatureLog.from_xml(log.to_xml)
      expect(reparsed.entries.map(&:class)).to eq(log.entries.map(&:class))
      expect(reparsed.entries.first).to eq(42)
      expect(reparsed.entries[1].number).to eq(1300.0)
    end
  end

  describe "value transformers (cast idempotence)" do
    it "keeps a model member built by transform: before the cast runs" do
      reading = UnionAttributeSpec::TransformedReading.from_yaml(<<~YAML)
        temp:
          number: 7.0
          unit: C
      YAML
      expect(reading.temp).to be_a(UnionAttributeSpec::TemperatureWithUnit)
      expect(reading.temp.number).to eq(7.0)
    end
  end
end
