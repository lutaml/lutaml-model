require "spec_helper"
require "lutaml/model/schema"

RSpec.describe "XSD Type Validation" do
  describe Lutaml::Model::Schema::XsBuiltinTypes do
    describe ".builtin?" do
      context "with primitive types" do
        it "recognizes xs:string" do
          expect(described_class.builtin?("xs:string")).to be true
        end

        it "recognizes xs:boolean" do
          expect(described_class.builtin?("xs:boolean")).to be true
        end

        it "recognizes xs:decimal" do
          expect(described_class.builtin?("xs:decimal")).to be true
        end

        it "recognizes xs:float" do
          expect(described_class.builtin?("xs:float")).to be true
        end

        it "recognizes xs:double" do
          expect(described_class.builtin?("xs:double")).to be true
        end

        it "recognizes xs:dateTime" do
          expect(described_class.builtin?("xs:dateTime")).to be true
        end

        it "recognizes xs:date" do
          expect(described_class.builtin?("xs:date")).to be true
        end

        it "recognizes xs:time" do
          expect(described_class.builtin?("xs:time")).to be true
        end

        it "recognizes xs:anyURI" do
          expect(described_class.builtin?("xs:anyURI")).to be true
        end

        it "recognizes xs:QName" do
          expect(described_class.builtin?("xs:QName")).to be true
        end
      end

      context "with derived types" do
        it "recognizes xs:integer" do
          expect(described_class.builtin?("xs:integer")).to be true
        end

        it "recognizes xs:ID" do
          expect(described_class.builtin?("xs:ID")).to be true
        end

        it "recognizes xs:IDREF" do
          expect(described_class.builtin?("xs:IDREF")).to be true
        end

        it "recognizes xs:token" do
          expect(described_class.builtin?("xs:token")).to be true
        end

        it "recognizes xs:NCName" do
          expect(described_class.builtin?("xs:NCName")).to be true
        end

        it "recognizes xs:long" do
          expect(described_class.builtin?("xs:long")).to be true
        end

        it "recognizes xs:int" do
          expect(described_class.builtin?("xs:int")).to be true
        end

        it "recognizes xs:short" do
          expect(described_class.builtin?("xs:short")).to be true
        end

        it "recognizes xs:byte" do
          expect(described_class.builtin?("xs:byte")).to be true
        end

        it "recognizes xs:positiveInteger" do
          expect(described_class.builtin?("xs:positiveInteger")).to be true
        end
      end

      context "with special types" do
        it "recognizes xs:anyType" do
          expect(described_class.builtin?("xs:anyType")).to be true
        end

        it "recognizes xs:anySimpleType" do
          expect(described_class.builtin?("xs:anySimpleType")).to be true
        end
      end

      context "with non-standard types" do
        it "rejects CustomType" do
          expect(described_class.builtin?("CustomType")).to be false
        end

        it "rejects MyType" do
          expect(described_class.builtin?("MyType")).to be false
        end

        it "rejects empty string" do
          expect(described_class.builtin?("")).to be false
        end

        it "rejects nil" do
          expect(described_class.builtin?(nil)).to be false
        end
      end
    end

    describe ".category" do
      it "returns :primitive for xs:string" do
        expect(described_class.category("xs:string")).to eq(:primitive)
      end

      it "returns :derived for xs:integer" do
        expect(described_class.category("xs:integer")).to eq(:derived)
      end

      it "returns :special for xs:anyType" do
        expect(described_class.category("xs:anyType")).to eq(:special)
      end

      it "returns nil for custom types" do
        expect(described_class.category("CustomType")).to be_nil
      end
    end
  end

  describe Lutaml::Model::Schema::XsdSchema do
    describe ".classify_xsd_type" do
      let(:register) { Lutaml::Model::Config.default_register }

      context "with standard XS types" do
        it "classifies xs:string as builtin" do
          model = Class.new(Lutaml::Model::Serializable)
          result = described_class.classify_xsd_type("xs:string", model, register)
          expect(result).to eq(:builtin)
        end

        it "classifies xs:integer as builtin" do
          model = Class.new(Lutaml::Model::Serializable)
          result = described_class.classify_xsd_type("xs:integer", model, register)
          expect(result).to eq(:builtin)
        end

        it "classifies xs:ID as builtin" do
          model = Class.new(Lutaml::Model::Serializable)
          result = described_class.classify_xsd_type("xs:ID", model, register)
          expect(result).to eq(:builtin)
        end
      end

      context "with custom types defined in nested models" do
        it "classifies resolvable custom type as custom" do
          nested_model = Class.new(Lutaml::Model::Serializable) do
            attribute :value, :string

            xml do
              root "NestedModel"
              type_name "CustomNestedType"
            end
          end

          parent_model = Class.new(Lutaml::Model::Serializable) do
            attribute :nested, nested_model
          end

          result = described_class.classify_xsd_type("CustomNestedType", parent_model, register)
          expect(result).to eq(:custom)
        end
      end

      context "with undefined custom types" do
        it "classifies undefined custom type as unresolvable" do
          model = Class.new(Lutaml::Model::Serializable)
          result = described_class.classify_xsd_type("UndefinedCustomType", model, register)
          expect(result).to eq(:unresolvable)
        end
      end
    end

    describe ".type_resolvable?" do
      let(:register) { Lutaml::Model::Config.default_register }

      it "returns true for type defined in nested model" do
        nested_model = Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            root "NestedModel"
            type_name "ResolvedType"
          end
        end

        parent_model = Class.new(Lutaml::Model::Serializable) do
          attribute :nested, nested_model
        end

        result = described_class.type_resolvable?("ResolvedType", parent_model, register)
        expect(result).to be true
      end

      it "returns false for undefined type" do
        model = Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string
        end

        result = described_class.type_resolvable?("UndefinedType", model, register)
        expect(result).to be false
      end
    end

    describe ".validate_xsd_types!" do
      let(:register) { Lutaml::Model::Config.default_register }

      context "with standard xs: types" do
        it "accepts model with xs:string attribute" do
          model = Class.new(Lutaml::Model::Serializable) do
            attribute :name, :string
          end

          expect {
            described_class.validate_xsd_types!(model, register)
          }.not_to raise_error
        end

        it "accepts model with xs:integer attribute" do
          model = Class.new(Lutaml::Model::Serializable) do
            attribute :count, :integer
          end

          expect {
            described_class.validate_xsd_types!(model, register)
          }.not_to raise_error
        end

        it "accepts model with multiple standard types" do
          model = Class.new(Lutaml::Model::Serializable) do
            attribute :name, :string
            attribute :count, :integer
            attribute :value, :float
            attribute :enabled, :boolean
          end

          expect {
            described_class.validate_xsd_types!(model, register)
          }.not_to raise_error
        end
      end

      context "with custom types from nested models" do
        it "accepts custom type defined in nested model" do
          nested_model = Class.new(Lutaml::Model::Serializable) do
            attribute :value, :string

            xml do
              root "NestedModel"
              type_name "ValidCustomType"
            end
          end

          parent_model = Class.new(Lutaml::Model::Serializable) do
            attribute :nested, nested_model
          end

          expect {
            described_class.validate_xsd_types!(parent_model, register)
          }.not_to raise_error
        end
      end

      context "with undefined custom types" do
        it "raises UnresolvableTypeError for undefined custom type" do
          custom_type = Class.new(Lutaml::Model::Type::String) do
            def self.xsd_type
              "UndefinedCustomType"
            end
          end

          model = Class.new(Lutaml::Model::Serializable) do
            attribute :custom_field, custom_type
          end

          expect {
            described_class.validate_xsd_types!(model, register)
          }.to raise_error(
            Lutaml::Model::UnresolvableTypeError,
            /Attribute 'custom_field' uses unresolvable xsd_type 'UndefinedCustomType'/
          )
        end

        it "includes helpful error message" do
          custom_type = Class.new(Lutaml::Model::Type::String) do
            def self.xsd_type
              "BadType"
            end
          end

          model = Class.new(Lutaml::Model::Serializable) do
            attribute :field, custom_type
          end

          expect {
            described_class.validate_xsd_types!(model, register)
          }.to raise_error(
            Lutaml::Model::UnresolvableTypeError,
            /Custom types must be defined as LutaML Type::Value or Model classes/
          )
        end

        it "reports multiple unresolvable types" do
          type1 = Class.new(Lutaml::Model::Type::String) do
            def self.xsd_type
              "BadType1"
            end
          end

          type2 = Class.new(Lutaml::Model::Type::String) do
            def self.xsd_type
              "BadType2"
            end
          end

          model = Class.new(Lutaml::Model::Serializable) do
            attribute :field1, type1
            attribute :field2, type2
          end

          expect {
            described_class.validate_xsd_types!(model, register)
          }.to raise_error(Lutaml::Model::UnresolvableTypeError) do |error|
            expect(error.message).to include("field1")
            expect(error.message).to include("field2")
            expect(error.message).to include("BadType1")
            expect(error.message).to include("BadType2")
          end
        end
      end

      context "with nested model validation" do
        it "validates types in nested models recursively" do
          bad_type = Class.new(Lutaml::Model::Type::String) do
            def self.xsd_type
              "NestedBadType"
            end
          end

          nested_model = Class.new(Lutaml::Model::Serializable) do
            attribute :bad_field, bad_type
          end

          parent_model = Class.new(Lutaml::Model::Serializable) do
            attribute :nested, nested_model
          end

          expect {
            described_class.validate_xsd_types!(parent_model, register)
          }.to raise_error(
            Lutaml::Model::UnresolvableTypeError,
            /In nested model.*NestedBadType/
          )
        end
      end
    end

    describe ".generate with validation" do
      let(:register) { Lutaml::Model::Config.default_register }

      it "validates types by default during XSD generation" do
        bad_type = Class.new(Lutaml::Model::Type::String) do
          def self.xsd_type
            "UnresolvableType"
          end
        end

        model = Class.new(Lutaml::Model::Serializable) do
          attribute :field, bad_type

          xml do
            root "TestModel"
          end
        end

        expect {
          described_class.generate(model)
        }.to raise_error(Lutaml::Model::UnresolvableTypeError)
      end

      it "allows skipping validation with skip_validation option" do
        bad_type = Class.new(Lutaml::Model::Type::String) do
          def self.xsd_type
            "UnresolvableType"
          end
        end

        model = Class.new(Lutaml::Model::Serializable) do
          attribute :field, bad_type

          xml do
            root "TestModel"
          end
        end

        expect {
          described_class.generate(model, skip_validation: true)
        }.not_to raise_error
      end

      it "successfully generates XSD for valid model" do
        model = Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :count, :integer

          xml do
            root "ValidModel"
          end
        end

        xsd = described_class.generate(model)
        expect(xsd).to match('<schema xmlns="http://www.w3.org/2001/XMLSchema">')
        expect(xsd).to include('type="xs:string"')
        expect(xsd).to include('type="xs:integer"')
      end
    end
  end
end