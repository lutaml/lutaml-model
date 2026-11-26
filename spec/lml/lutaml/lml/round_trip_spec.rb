# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "tempfile"

RSpec.describe "Round-trip: class definitions and instances" do
  def with_lml_file(content)
    file = Tempfile.new(%w[test .lml])
    file.write(content)
    file.rewind
    yield file
  ensure
    file.close!
  end

  describe "class definition round-trip" do
    it "compiles a class, instantiates it, and the instance survives serialization" do
      lml_models = <<~LML
        models WidgetStore {
          class Widget {
            attribute name {
              type String
              cardinality 1
            }
            attribute weight {
              type Float
              cardinality 0..1
            }
            attribute tags {
              type String
              cardinality 0..n
            }
          }
        }
      LML

      with_lml_file(lml_models) do |f|
        compiled = Lutaml::Lml.compile(f)
        widget_cls = compiled["Widget"]
        obj = widget_cls.new(name: "Gear", weight: 3.14, tags: %w[metal heavy])
        expect(obj.name).to eq("Gear")
        expect(obj.weight).to eq(3.14)
        expect(obj.tags).to eq(%w[metal heavy])
      end
    end

    it "round-trips a compiled class with primitive attributes through to_lml/from_lml" do
      require "lutaml/lml/format"

      lml_models = <<~LML
        models ProductStore {
          class Product {
            attribute sku {
              type String
              cardinality 1
            }
            attribute price {
              type Float
              cardinality 1
            }
            attribute discontinued {
              type Boolean
              cardinality 0..1
            }
          }
        }
      LML

      with_lml_file(lml_models) do |f|
        compiled = Lutaml::Lml.compile(f)
        product_cls = compiled["Product"]

        original = product_cls.new(sku: "ABC-123", price: 29.99, discontinued: false)
        lml_text = original.to_lml
        restored = product_cls.from_lml(lml_text)
        expect(restored.sku).to eq("ABC-123")
        expect(restored.price).to eq(29.99)
        expect(restored.discontinued).to eq(false)
      end
    end

    # The emit side's quoting contract against the grammar's `word`
    # rule: bare emission only for runs of [A-Za-z0-9_]; everything
    # else must be quoted AND survive the parse back (values that the
    # grammar cannot re-parse bare are quoted exactly so this
    # round-trip holds).
    describe "string quoting contract" do
      require "lutaml/lml/format"

      let(:lml_models) do
        <<~LML
          models QuoteStore {
            class Quote {
              attribute value { type String cardinality 1 }
            }
          }
        LML
      end

      def round_trip(value)
        with_lml_file(lml_models) do |f|
          klass = Lutaml::Lml.compile(f)["Quote"]
          klass.from_lml(klass.new(value: value).to_lml).value
        end
      end

      { 'bare words stay bare': %w[gear ABC123 v2_1 x42],
        'non-word values are quoted and re-parsed':
          ["ABC-123", "2012-03-15", "has space", "it's", 'he said "hi"', ""],
        'escaped values round-trip':
          ['Raku "kiln" fired', %(both " and '), "C:\\Users\\marie", "say \"hi\" and 'bye'"],
        'quoted padding is content':
          [" padded ", "left ", " right", "   "] }.each do |label, values|
        it "round-trips #{label}" do
          values.each { |v| expect(round_trip(v)).to eq(v) }
        end
      end
    end

    it "compiles and instantiates nested classes" do
      lml_models = <<~LML
        models NestedStore {
          class Address {
            attribute city {
              type String
              cardinality 1
            }
            attribute country {
              type String
              cardinality 1
            }
          }
          class Person {
            attribute name {
              type String
              cardinality 1
            }
            attribute home {
              type Address
              cardinality 1
            }
          }
        }
      LML

      with_lml_file(lml_models) do |f|
        compiled = Lutaml::Lml.compile(f)
        person_cls = compiled["Person"]
        address_cls = compiled["Address"]

        addr = address_cls.new(city: "Tokyo", country: "JP")
        person = person_cls.new(name: "Akiko", home: addr)

        expect(person.name).to eq("Akiko")
        expect(person.home.city).to eq("Tokyo")
        expect(person.home.country).to eq("JP")
      end
    end

    it "round-trips an enum through compile → instantiate → value check" do
      lml_models = <<~LML
        models Enums {
          enum Status {
            active
            inactive
            pending
          }
        }
      LML

      with_lml_file(lml_models) do |f|
        compiled = Lutaml::Lml.compile(f)
        status_cls = compiled["Status"]

        expect(status_cls.active.value).to eq("active")
        expect(status_cls.inactive.value).to eq("inactive")
        expect(status_cls.pending.value).to eq("pending")
      end
    end
  end

  describe "instance definition round-trip" do
    it "parses an instance and extracts typed attributes including floats and booleans" do
      lml = <<~LML
        instance Sensor {
          type Thermometer
          location = "lab-3"
          reading = 23.5
          active = true
        }
      LML

      with_lml_file(lml) do |f|
        doc = Lutaml::Lml.parse_document(f)
        inst = doc.instance
        expect(inst.type).to eq("Sensor")

        attrs = inst.attributes.to_h { |a| [a.name, a.value] }
        expect(attrs["type"]).to eq("Thermometer")
        expect(attrs["location"]).to eq("lab-3")
        expect(attrs["reading"]).to eq(23.5)
        expect(attrs["active"]).to eq(true)
      end
    end

    it "parses an instance with array values" do
      lml = <<~LML
        instance Checklist {
          type AuditList
          items = ["verify", "validate", "report"]
        }
      LML

      with_lml_file(lml) do |f|
        doc = Lutaml::Lml.parse_document(f)
        inst = doc.instance
        items = inst.attributes.find { |a| a.name == "items" }
        expect(items.value).to eq(%w[verify validate report])
      end
    end

    it "parses nested instances" do
      lml = <<~LML
        instance Container {
          instance Inner {
            type Config
            key = "value"
          }
        }
      LML

      with_lml_file(lml) do |f|
        doc = Lutaml::Lml.parse_document(f)
        inner = doc.instance.instance
        expect(inner.type).to eq("Inner")
        inner_attrs = inner.attributes.to_h { |a| [a.name, a.value] }
        expect(inner_attrs["type"]).to eq("Config")
        expect(inner_attrs["key"]).to eq("value")
      end
    end

    it "round-trips instance data through format adapter with floats and booleans" do
      require "lutaml/lml/format"

      model_class = Class.new(Lutaml::Model::Serializable) do
        attribute :sensor_id, :string
        attribute :reading, :float
        attribute :active, :boolean, default: true

        lml do
          map :sensor_id, to: :sensor_id
          map :reading, to: :reading
          map :active, to: :active
        end
      end

      original = model_class.new(sensor_id: "TH-042", reading: 21.7, active: false)
      lml_text = original.to_lml

      restored = model_class.from_lml(lml_text)
      expect(restored.sensor_id).to eq("TH-042")
      expect(restored.reading).to eq(21.7)
      expect(restored.active).to eq(false)
    end

    it "round-trips real-world instance data (data_s158_metadata)" do
      require "lutaml/lml/format"

      doc = Lutaml::Lml.parse_document(File.new("spec/lml/fixtures/lml/data_s158_metadata.lml"))
      inner = doc.instance.instance
      expect(inner.type).to eq("IhoDataModels::IhoMetadata")

      attrs = inner.attributes.to_h { |a| [a.name, a.value] }
      expect(attrs["document_number"]).to eq("S-158:102")
      expect(attrs["title"]).to eq("Bathymetric Surface Validation Checks")
    end
  end

  describe "compiled class + instance validation" do
    let(:compiler) { Lutaml::Lml::ModelCompiler.new }

    it "accepts a valid instance against a compiled class" do
      lml = <<~LML
        models Valid {
          class Sensor {
            attribute id {
              type String
              cardinality 1
            }
            attribute label {
              type String
              cardinality 0..1
            }
          }
        }
      LML

      with_lml_file(lml) do |f|
        errors = compiler.validate(f)
        expect(errors).to eq([])
      end
    end

    it "detects unknown type reference in instance" do
      instance_lml = <<~LML
        instance MyGadget {
          type NonExistent
          name = "hello"
        }
      LML

      with_lml_file(instance_lml) do |f|
        errors = compiler.validate(f)
        expect(errors).to include(a_string_matching(/unknown type 'NonExistent'/))
      end
    end

    it "detects unknown attributes on an instance" do
      models_lml = <<~LML
        models Strict {
          class Sensor {
            attribute id {
              type String
              cardinality 1
            }
          }
        }
      LML

      instance_lml = <<~LML
        instance BadSensor {
          type Sensor
          id = "s-001"
          bogus_field = "oops"
        }
      LML

      compiled = nil
      with_lml_file(models_lml) do |f|
        compiled = Lutaml::Lml.compile(f)
      end

      with_lml_file(instance_lml) do |f|
        errors = compiler.validate(f, compiled: compiled)
        expect(errors).to include(a_string_matching(/bogus_field.*not defined/))
      end
    end

    it "detects missing required attributes" do
      models_lml = <<~LML
        models Required {
          class Account {
            attribute email {
              type String
              cardinality 1
            }
            attribute nickname {
              type String
              cardinality 0..1
            }
          }
        }
      LML

      instance_lml = <<~LML
        instance IncompleteAccount {
          type Account
          nickname = "bob"
        }
      LML

      compiled = nil
      with_lml_file(models_lml) do |f|
        compiled = Lutaml::Lml.compile(f)
      end

      with_lml_file(instance_lml) do |f|
        errors = compiler.validate(f, compiled: compiled)
        expect(errors).to include(a_string_matching(/email.*required/))
      end
    end

    it "validates nested instances recursively" do
      models_lml = <<~LML
        models Nested {
          class Outer {
            attribute name {
              type String
              cardinality 1
            }
          }
        }
      LML

      instance_lml = <<~LML
        instance Wrapper {
          instance Inner {
            type Outer
            wrong_attr = "oops"
          }
        }
      LML

      compiled = nil
      with_lml_file(models_lml) do |f|
        compiled = Lutaml::Lml.compile(f)
      end

      with_lml_file(instance_lml) do |f|
        errors = compiler.validate(f, compiled: compiled)
        expect(errors).to include(a_string_matching(/wrong_attr.*not defined/))
      end
    end

    it "validates against real-world fixtures" do
      instance_lml = <<~LML
        instance TestMeta {
          type IhoMetadata
          document_number = "S-101"
          title = "Test Document"
          unknown_field = "should fail"
        }
      LML

      compiled = Lutaml::Lml.compile(File.new("spec/lml/fixtures/lml/iho_data_models.lml"))

      with_lml_file(instance_lml) do |f|
        errors = compiler.validate(f, compiled: compiled)
        expect(errors).to include(a_string_matching(/unknown_field.*not defined/))
      end
    end
  end

  describe "view document YAML round trip" do
    it "survives to_yaml/from_yaml with filters and imports intact" do
      doc = Lutaml::Lml::Document.new(
        name: "V",
        title: "T",
        classes: [Lutaml::Lml::UmlClass.new(name: "Foo", definition: "a \\{ b \\}")],
        show_filter: Lutaml::Lml::ViewFilter.new(entity_names: ["Foo"]),
        view_imports: [Lutaml::Lml::ViewImport.new(path: "m.lutaml")],
      )

      restored = Lutaml::Lml::Document.from_yaml(doc.to_yaml)

      aggregate_failures do
        expect(restored.name).to eq("V")
        expect(restored.title).to eq("T")
        expect(restored.classes.map(&:name)).to eq(["Foo"])
        expect(restored.classes.first.definition).to eq("a { b }")
        expect(restored.show_filter.entity_names).to eq(["Foo"])
        expect(restored.view_imports.map(&:path)).to eq(["m.lutaml"])
      end
    end
  end
end
