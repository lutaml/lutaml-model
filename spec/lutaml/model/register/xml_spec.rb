require "spec_helper"
require_relative "../../../support/xml_mapping_namespaces"

module RegisterXmlSpec
  class String < Lutaml::Model::Type::String
    def to_xml
      "custom_string: #{value}"
    end
  end

  class Mi < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "mi"
      namespace MathMlNamespace

      map_content to: :value
    end
  end

  # Define a MathML Operator element class
  class Mo < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "mo"
      namespace MathMlNamespace

      map_content to: :value
    end
  end

  # Define a MathML Fraction element
  class Mfrac < Lutaml::Model::Serializable
    attribute :numerator, :mo
    attribute :denominator, :mi

    xml do
      element "mfrac"
      namespace MathMlNamespace

      map_element "mo", to: :numerator
      map_element "mi", to: :denominator
    end
  end

  # Define a full MathML expression
  class Math < Lutaml::Model::Serializable
    attribute :symbol, :mi
    attribute :operator, :mo
    attribute :fraction, :mfrac

    xml do
      element "math"
      namespace MathMlNamespace

      map_element "mi", to: :symbol
      map_element "mo", to: :operator
      map_element "mfrac", to: :fraction
    end
  end

  class NewMi < Lutaml::Model::Serializable
    attribute :value, :string
    attribute :color, :string

    xml do
      element "mi"
      namespace MathMlNamespace

      map_content to: :value
      map_attribute :color, to: :color
    end
  end
end

RSpec.describe "RegisterXmlSpec" do
  let(:register) { Lutaml::Model::Register.new(:mathml_register) }
  let(:formula) { RegisterXmlSpec::Math.from_xml(xml, register: register) }

  before do
    # Register the register in the global registry
    Lutaml::Model::GlobalRegister.register(register)

    # Register all the model classes with explicit IDs matching attribute types
    register.register_model(RegisterXmlSpec::Math, id: :math)
    register.register_model(RegisterXmlSpec::Mi, id: :mi)
    register.register_model(RegisterXmlSpec::Mo, id: :mo)
    register.register_model(RegisterXmlSpec::Mfrac, id: :mfrac)
  end

  describe "parsing MathML XML" do
    let(:xml) do
      <<~XML
        <math xmlns="http://www.w3.org/1998/Math/MathML">
          <mi>x</mi>
          <mo>=</mo>
          <mfrac>
            <mo>a</mo>
            <mi>b</mi>
          </mfrac>
        </math>
      XML
    end

    let(:instantiated) do
      register.get_class(:math).new(
        symbol: RegisterXmlSpec::Mi.new(value: "x"),
        operator: RegisterXmlSpec::Mo.new(value: "="),
        fraction: RegisterXmlSpec::Mfrac.new(
          {
            numerator: RegisterXmlSpec::Mo.new(value: "a"),
            denominator: RegisterXmlSpec::Mi.new(value: "b"),
            __register: register,
          },
        ),
      )
    end

    it "parses MathML XML into model objects" do
      expect(formula).to be_a(RegisterXmlSpec::Math)
      expect(formula.symbol.value).to eq("x")
      expect(formula.operator.value).to eq("=")
      expect(formula.fraction.numerator.value).to eq("a")
      expect(formula.fraction.denominator.value).to eq("b")
    end

    it "serializes model objects back to MathML XML" do
      expect(formula.to_xml).to be_xml_equivalent_to(xml)
    end

    it "instantiates the model correctly" do
      expect(instantiated.to_xml).to be_xml_equivalent_to(xml)
    end
  end

  describe "using global type substitution with MathML" do
    let(:register_substitution) do
      register.register_global_type_substitution(
        from_type: RegisterXmlSpec::Mi,
        to_type: RegisterXmlSpec::NewMi,
      )
      register.register_global_type_substitution(
        from_type: Lutaml::Model::Type::String,
        to_type: RegisterXmlSpec::String,
      )
    end

    let(:xml) do
      <<~XML
        <math xmlns="http://www.w3.org/1998/Math/MathML">
          <mi color="red">y</mi>
        </math>
      XML
    end

    let(:xml_type_substituted) do
      <<~XML
        <math xmlns="http://www.w3.org/1998/Math/MathML">
          <mi color="custom_string: red">y</mi>
        </math>
      XML
    end

    context "when substitute class is not registered" do
      it "serializes mi tag using Mi class" do
        expect(formula.symbol).to be_a(RegisterXmlSpec::Mi)
        expect(formula.symbol).not_to respond_to(:color)
        expect(formula.symbol.value).to eq("y")
        expect(formula.to_xml).not_to be_xml_equivalent_to(xml)
      end
    end

    context "when substitute class is registered" do
      it "serializes mi tag using NewMi class" do
        register_substitution
        expect(formula.symbol).to be_a(RegisterXmlSpec::NewMi)
        expect(formula.symbol).to respond_to(:color)
        expect(formula.symbol.color).to eq("red")
        expect(formula.symbol.value).to eq("y")
        expect(formula.to_xml).to be_xml_equivalent_to(xml_type_substituted)
      end
    end
  end
end
