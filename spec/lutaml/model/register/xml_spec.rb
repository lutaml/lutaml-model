require "spec_helper"

module RegisterXmlSpec
  class Mi < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      root "mi"
      namespace "http://www.w3.org/1998/Math/MathML"

      map_content to: :value
    end
  end

  # Define a MathML Operator element class
  class Mo < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      root "mo"
      namespace "http://www.w3.org/1998/Math/MathML"

      map_content to: :value
    end
  end

  # Define a MathML Fraction element
  class Mfrac < Lutaml::Model::Serializable
    attribute :numerator, :mo
    attribute :denominator, :mi

    xml do
      root "mfrac"
      namespace "http://www.w3.org/1998/Math/MathML"

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
      root "math"
      namespace "http://www.w3.org/1998/Math/MathML"

      map_element "mi", to: :symbol
      map_element "mo", to: :operator
      map_element "mfrac", to: :fraction
    end
  end

  class NewMi < Lutaml::Model::Serializable
    attribute :value, :string
    attribute :color, :string

    xml do
      root "mi"
      namespace "http://www.w3.org/1998/Math/MathML"

      map_content to: :value
      map_attribute :color, to: :color
    end
  end
end

RSpec.describe "XML MathML with Register" do
  let(:register) { Lutaml::Model::Register.new(:mathml_register) }
  let(:formula) { RegisterXmlSpec::Math.from_xml(xml, register: register) }

  before do
    # Register the register in the global registry
    Lutaml::Model::GlobalRegister.register(register)

    # Register all the model classes
    register.register_model_tree(RegisterXmlSpec::Math)
    register.register_model(RegisterXmlSpec::Mi)
    register.register_model(RegisterXmlSpec::Mo)
    register.register_model(RegisterXmlSpec::Mfrac)
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

    it "parses MathML XML into model objects" do
      expect(formula).to be_a(RegisterXmlSpec::Math)
      expect(formula.symbol.value).to eq("x")
      expect(formula.operator.value).to eq("=")
      expect(formula.fraction.numerator.value).to eq("a")
      expect(formula.fraction.denominator.value).to eq("b")
    end

    it "serializes model objects back to MathML XML" do
      expect(formula.to_xml).to be_equivalent_to(xml)
    end
  end

  describe "using global type substitution with MathML" do
    let(:register_substitution) do
      register.register_global_type_substitution(
        from_type: RegisterXmlSpec::Mi,
        to_type: RegisterXmlSpec::NewMi
      )
    end

    let(:xml) do
      <<~XML
        <math xmlns="http://www.w3.org/1998/Math/MathML">
          <mi color="red">y</mi>
        </math>
      XML
    end

    context "before registering substitute class" do
      it "serializes mi tag using Mi class" do
        expect(formula.symbol).to be_a(RegisterXmlSpec::Mi)
        expect(formula.symbol).not_to respond_to(:color)
        expect(formula.symbol.value).to eq("y")
        expect(formula.to_xml).not_to be_equivalent_to(xml)
      end
    end

    context "after registering substitute class" do
      it "serializes mi tag using NewMi class" do
        register_substitution
        expect(formula.symbol).to be_a(RegisterXmlSpec::NewMi)
        expect(formula.symbol).to respond_to(:color)
        expect(formula.symbol.color).to eq("red")
        expect(formula.symbol.value).to eq("y")
        expect(formula.to_xml).to be_equivalent_to(xml)
      end
    end
  end

  # describe "handling complex MathML expressions" do
  #   let(:complex_xml) do
  #     <<~XML
  #       <math xmlns="http://www.w3.org/1998/Math/MathML">
  #         <mi>f</mi>
  #         <mo>(</mo>
  #         <mi>x</mi>
  #         <mo>)</mo>
  #         <mo>=</mo>
  #         <mfrac>
  #           <mi>1</mi>
  #           <mi>1+x²</mi>
  #         </mfrac>
  #       </math>
  #     XML
  #   end

  #   # This test would require a more sophisticated MathML model
  #   # but demonstrates the concept of handling more complex expressions
  #   it "shows limitation of simple model with complex expressions" do
  #     # This would fail with the current model since it doesn't handle
  #     # the full formula structure, but illustrates the need for a more
  #     # complete MathML implementation
  #     expect {
  #       RegisterXmlSpec::Math.from_xml(complex_xml, register: register)
  #     }.not_to raise_error
  #   end
  # end
end
