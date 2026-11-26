# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "tempfile"

RSpec.describe Lutaml::Lml::ModelCompiler do
  let(:compiler) { described_class.new }

  describe ".compile" do
    it "compiles LML model definitions into Serializable subclasses" do
      file = Tempfile.new(%w[test .lml])
      file.write("models TestModels {\n  class Widget {\n    attribute name {\n      type String\n      cardinality 1\n    }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      expect(result).to have_key("Widget")
      expect(result["Widget"]).to be < Lutaml::Model::Serializable
      expect(result["Widget"].attributes).to have_key(:name)
      file.close!
    end

    it "compiles classes from diagram syntax" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test {\n  class Foo {\n    +bar: String[0..1]\n    +baz: Integer[1..*]\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      foo = result["Foo"]
      expect(foo.attributes[:bar].collection?).to be_falsey
      expect(foo.attributes[:baz].collection?).to be_truthy
      file.close!
    end

    it "resolves standard types correctly" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Types {\n  class Typed {\n    attribute s { type String cardinality 1 }\n    attribute b { type Boolean cardinality 0..1 }\n    attribute i { type Integer cardinality 1 }\n    attribute d { type date_time cardinality 1 }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      typed = result["Typed"]
      obj = typed.new("s" => "hello", "b" => true, "i" => 42)
      expect(obj.s).to eq("hello")
      expect(obj.b).to eq(true)
      expect(obj.i).to eq(42)
      file.close!
    end

    it "offers no lutaml-model :hash mapping for any DSL type name" do
      expect(described_class::TYPE_MAP.values).not_to include(:hash)
    end

    it "handles collection cardinality" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Coll {\n  class Container {\n    attribute items { type String cardinality 0..n }\n    attribute single { type String cardinality 1 }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      container = result["Container"]
      expect(container.attributes[:items].collection?).to be_truthy
      expect(container.attributes[:single].collection?).to be_falsey
      file.close!
    end

    it "resolves custom types from compiled classes" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Nested {\n  class Inner {\n    attribute val { type String cardinality 1 }\n  }\n  class Outer {\n    attribute inner { type Inner cardinality 1 }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      expect(result["Inner"]).to be < Lutaml::Model::Serializable
      expect(result["Outer"]).to be < Lutaml::Model::Serializable
      file.close!
    end

    it "handles reference types as strings" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Ref {\n  class Item {\n    attribute ref { type reference:(Other.id) cardinality 0..n }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      expect(result["Item"].attributes[:ref].collection?).to be_truthy
      file.close!
    end

    it "compiles enums with value constants" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Enums {\n  enum Color {\n    red\n    green\n    blue\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      expect(result["Color"]).to be < Lutaml::Model::Serializable
      expect(result["Color"].red.value).to eq("red")
      expect(result["Color"].green.value).to eq("green")
      file.close!
    end

    it "compiles data types" do
      file = Tempfile.new(%w[test .lml])
      file.write("diagram Test {\n  data_type Uri {\n    definition { URI }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      expect(result["Uri"]).to be < Lutaml::Model::Serializable
      file.close!
    end

    it "registers classes in a namespace" do
      mod = Module.new
      file = Tempfile.new(%w[test .lml])
      file.write("models NS {\n  class Item {\n    attribute name { type String cardinality 1 }\n  }\n}")
      file.rewind

      described_class.new(namespace: mod).compile(file)
      expect(mod.const_defined?(:Item)).to be true
      obj = mod::Item.new("name" => "test")
      expect(obj.name).to eq("test")
      file.close!
    end

    it "creates the default namespace nested under Lutaml::Lml" do
      file = Tempfile.new(%w[test .lml])
      file.write("models NS {\n  class Item {\n    attribute name { type String cardinality 1 }\n  }\n}")
      file.rewind

      ns = described_class::DEFAULT_NAMESPACE
      result = described_class.new(namespace: ns).compile(file)
      mod = Object.const_get(ns)
      expect(result["Item"].name).to eq("Lutaml::Lml::Generated::Item")
      expect(mod.const_defined?(:Item)).to be true
      file.close!
    end

    it "creates intermediate modules for a scoped namespace string" do
      ns = "LmlScopedSpec::Inner"
      file = Tempfile.new(%w[test .lml])
      file.write("models NS {\n  class Item {\n    attribute name { type String cardinality 1 }\n  }\n}")
      file.rewind

      described_class.new(namespace: ns).compile(file)
      expect(LmlScopedSpec::Inner::Item.name)
        .to eq("LmlScopedSpec::Inner::Item")
      file.close!
    end

    it "resolves a string namespace into a real module" do
      ns = "LmlSpecNamespace"
      file = Tempfile.new(%w[test .lml])
      file.write("models NS {\n  class Item {\n    attribute name { type String cardinality 1 }\n  }\n}")
      file.rewind

      described_class.new(namespace: ns).compile(file)
      expect(Object.const_get(ns)::Item.name).to eq("#{ns}::Item")
      file.close!
    end

    it "produces classes that generate JSON and YAML Schema" do
      require "lutaml/model/schema"
      file = Tempfile.new(%w[test .lml])
      file.write(<<~LML)
        models Schemas {
          class Widget {
            attribute name { type String cardinality 1 }
            attribute color { type Color cardinality 0..1 }
            attribute parts { type Integer cardinality 0..n }
          }
          enum Color {
            RED
            GREEN
          }
        }
      LML
      file.rewind

      result = described_class.new(namespace: "LmlSchemaSpec").compile(file)
      parsed = JSON.parse(Lutaml::Model::Schema.to_json(result["Widget"]))
      expect(parsed["$ref"]).to eq("#/$defs/LmlSchemaSpec_Widget")
      defs = parsed["$defs"]
      expect(defs["LmlSchemaSpec_Widget"]["properties"]["parts"]["type"]).to eq("array")
      expect(defs["LmlSchemaSpec_Color"]["properties"]["value"]["enum"]).to eq(%w[RED GREEN])

      expect(Lutaml::Model::Schema.to_yaml(result["Widget"])).to start_with("%YAML 1.1")
      file.close!
    end

    context "when attributes reference other models (issue #49)" do
      let(:lml) do
        <<~LML
          class Concept {
            related: RelatedConcept [0..*]
            origin: RelatedConcept
            name: String [1..1]
          }
          class RelatedConcept {
            id: String
          }
        LML
      end

      [nil, "LmlRefSpec"].each do |namespace|
        it "emits $ref to the referenced definition (namespace: #{namespace.inspect})" do
          require "lutaml/model/schema"
          result = described_class.new(namespace: namespace).compile(lml)
          parsed = YAML.safe_load(Lutaml::Model::Schema.to_yaml(result["Concept"]))
          prefix = namespace ? "#{namespace}_" : ""
          props = parsed["$defs"]["#{prefix}Concept"]["properties"]

          expect(props["related"]).to eq(
            "type" => "array", "items" => { "$ref" => "#/$defs/#{prefix}RelatedConcept" },
          )
          expect(props["origin"]).to eq("$ref" => "#/$defs/#{prefix}RelatedConcept")
          expect(parsed["$defs"]).to have_key("#{prefix}RelatedConcept")
        end
      end
    end

    context "with the issue #49 namespace and `as :element` syntax" do
      let(:lml) do
        <<~LML
          class Car {
            namespace "xyz"
            wheels Wheel[4] as :element
            vin: String as :attribute
          }
          class Wheel {
            tire
          }
        LML
      end

      it "carries the namespace and element/attribute kinds into the XML mapping" do
        car = described_class.new.compile(lml)["Car"]
        mapping = car.mappings_for(:xml)

        expect(mapping.namespace_uri).to eq("xyz")
        expect(mapping.elements.map(&:name)).to eq(["wheels"])
        expect(mapping.attributes.map(&:name)).to eq(["vin"])
      end

      it "does not turn namespace or `as` into string properties" do
        car = described_class.new.compile(lml)["Car"]
        expect(car.attributes.keys).to contain_exactly(:wheels, :vin)
      end

      it "generates a YAML Schema with only the declared properties" do
        require "lutaml/model/schema"
        car = described_class.new.compile(lml)["Car"]
        props = YAML.safe_load(Lutaml::Model::Schema.to_yaml(car))["$defs"]["Car"]["properties"]

        expect(props.keys).to contain_exactly("wheels", "vin")
        expect(props["wheels"]["items"]).to eq("$ref" => "#/$defs/Wheel")
      end

      it "keeps the namespace on an empty class" do
        klass = described_class.new.compile("class Empty {\n namespace \"xyz\"\n}\n")["Empty"]
        expect(klass.mappings_for(:xml).namespace_uri).to eq("xyz")
      end

      it "keeps an attribute literally named namespace" do
        klass = described_class.new.compile("class A {\n  namespace: String\n}\n")["A"]
        expect(klass.attributes.keys).to eq([:namespace])
      end
    end
  end

  describe "Lutaml::Lml.compile" do
    it "provides module-level compile method" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Top {\n  class Thing {\n    attribute x { type String cardinality 1 }\n  }\n}")
      file.rewind

      result = Lutaml::Lml.compile(file)
      expect(result).to have_key("Thing")
      file.close!
    end
  end

  describe ".hydrate" do
    it "hydrates a compiled class from instance data" do
      file = Tempfile.new(%w[test .lml])
      file.write("models H {\n  class Sensor {\n    attribute name { type String cardinality 1 }\n    attribute reading { type Float cardinality 0..1 }\n  }\n}")
      file.rewind

      compiler.compile(file)
      file.rewind

      instance_lml = Tempfile.new(%w[inst .lml])
      instance_lml.write("instance MySensor {\n  instance Sensor {\n    name = \"TH-042\"\n    reading = 23.5\n  }\n}")
      instance_lml.rewind

      result = compiler.hydrate(instance_lml)
      expect(result).to be_a(compiler.compiled_classes["Sensor"])
      expect(result.name).to eq("TH-042")
      expect(result.reading).to eq(23.5)

      file.close!
      instance_lml.close!
    end

    it "hydrates nested instances" do
      models_lml = Tempfile.new(%w[mod .lml])
      models_lml.write("models Nested {\n  class Address {\n    attribute city { type String cardinality 1 }\n  }\n  class Person {\n    attribute name { type String cardinality 1 }\n    attribute addresses { type Address cardinality 0..n }\n  }\n}")
      models_lml.rewind

      compiler.compile(models_lml)

      instance_lml = Tempfile.new(%w[inst .lml])
      instance_lml.write("instance Wrapper {\n  instance Person {\n    name = \"Alice\"\n    addresses = [\n      instance Address {\n        city = \"Tokyo\"\n      },\n      instance Address {\n        city = \"Osaka\"\n      }\n    ]\n  }\n}")
      instance_lml.rewind

      result = compiler.hydrate(instance_lml)
      expect(result.name).to eq("Alice")
      expect(result.addresses.length).to eq(2)
      expect(result.addresses[0]).to be_a(compiler.compiled_classes["Address"])
      expect(result.addresses[0].city).to eq("Tokyo")
      expect(result.addresses[1].city).to eq("Osaka")

      models_lml.close!
      instance_lml.close!
    end

    it "hydrates array instances" do
      file = Tempfile.new(%w[test .lml])
      file.write("models Arr {\n  class Item {\n    attribute label { type String cardinality 1 }\n  }\n  class Box {\n    attribute items { type Item cardinality 0..n }\n  }\n}")
      file.rewind

      compiler.compile(file)
      file.rewind

      instance_lml = Tempfile.new(%w[inst .lml])
      instance_lml.write("instance MyBox {\n  instance Box {\n    items = [\n      instance Item {\n        label = \"first\"\n      },\n      instance Item {\n        label = \"second\"\n      }\n    ]\n  }\n}")
      instance_lml.rewind

      result = compiler.hydrate(instance_lml)
      expect(result).to be_a(compiler.compiled_classes["Box"])
      expect(result.items.length).to eq(2)
      expect(result.items[0].label).to eq("first")
      expect(result.items[1].label).to eq("second")

      file.close!
      instance_lml.close!
    end

    it "hydrates real-world IHO metadata" do
      compiler.compile(File.new("spec/lml/fixtures/lml/iho_data_models.lml"))

      result = compiler.hydrate(File.new("spec/lml/fixtures/lml/data_s158_metadata.lml"))
      expect(result).to be_a(compiler.compiled_classes["IhoMetadata"])
      expect(result.document_number).to eq("S-158:102")
      expect(result.title).to eq("Bathymetric Surface Validation Checks")
      expect(result.compliant_standards.length).to eq(2)
      expect(result.compliant_standards[0]).to be_a(compiler.compiled_classes["CompliantStandard"])
      expect(result.compliant_standards[0].title).to eq("S-102 PS")
    end

    it "returns a hash for unknown types" do
      instance_lml = Tempfile.new(%w[inst .lml])
      instance_lml.write("instance Mystery {\n  type UnknownType\n  name = \"test\"\n}")
      instance_lml.rewind

      result = compiler.hydrate(instance_lml)
      expect(result).to be_a(Hash)
      expect(result[:name]).to eq("test")

      instance_lml.close!
    end
  end

  describe "with real-world fixtures" do
    it "compiles iho_data_models.lml" do
      result = Lutaml::Lml.compile(File.new("spec/lml/fixtures/lml/iho_data_models.lml"))
      expect(result.keys).to contain_exactly("IhoMetadata", "CompliantStandard")

      meta = result["IhoMetadata"]
      obj = meta.new("document_number" => "S-101", "title" => "Test")
      expect(obj.document_number).to eq("S-101")
      expect(obj.title).to eq("Test")
      expect(meta.attributes[:compliant_standards].collection?).to be true
    end

    it "compiles iho_s102_check.lml" do
      result = Lutaml::Lml.compile(File.new("spec/lml/fixtures/lml/iho_s102_check.lml"))
      expect(result.keys).to contain_exactly("ValidationChecks", "ValidationCheck")

      vc = result["ValidationCheck"]
      expect(vc.attributes[:data_quality_measure].collection?).to be true
      expect(vc.attributes[:prerequisites].collection?).to be true
      expect(vc.attributes[:dev_id].collection?).to be false
    end
  end

  describe "declared mapping blocks" do
    it "emits lutaml-model wire-name mappings" do
      file = Tempfile.new(%w[test .lml])
      file.write("models M {\n  class Widget {\n    attribute name { type String cardinality 1 }\n    mapping yaml { map \"full-name\", to: \"name\" }\n  }\n}")
      file.rewind

      result = compiler.compile(file)
      widget = result["Widget"]
      expect(widget.attributes).to have_key(:name)
      wired = widget.from_yaml("---\nfull-name: Gizmo\n")
      expect(wired.name).to eq("Gizmo")
      file.close!
    end
  end
end
