# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/lutaml/model"

RSpec.describe "Namespace declaration placement (no hoisting)" do
  # Regression test: child element's default namespace declaration must NOT
  # be hoisted to the parent element during round-trip serialization.
  #
  # Input:  <stem><math xmlns="http://www.w3.org/1998/Math/MathML">T</math></stem>
  # Wrong:  <stem xmlns="http://www.w3.org/1998/Math/MathML"><math>T</math></stem>
  # Right:  xmlns stays on <math>, not on <stem>

  let(:mathml_namespace) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "http://www.w3.org/1998/Math/MathML"
    end
  end

  let(:math_class) do
    ns = mathml_namespace
    Class.new do
      include Lutaml::Model::Serialize

      attribute :content, :string

      xml do
        element "math"
        namespace ns
        map_content to: :content
      end

      def self.name
        "MathElement"
      end
    end
  end

  let(:stem_class) do
    math = math_class
    Class.new do
      include Lutaml::Model::Serialize

      attribute :block, :string
      attribute :type, :string
      attribute :math, math

      xml do
        element "stem"
        map_attribute "block", to: :block
        map_attribute "type", to: :type
        map_element "math", to: :math
      end

      def self.name
        "StemElement"
      end
    end
  end

  let(:input_xml) do
    <<~XML
      <stem block="false" type="MathML">
        <math xmlns="http://www.w3.org/1998/Math/MathML">T</math>
      </stem>
    XML
  end

  it "keeps xmlns on child element, not hoisted to parent" do
    parsed = stem_class.from_xml(input_xml)

    expect(parsed.block).to eq("false")
    expect(parsed.type).to eq("MathML")
    expect(parsed.math.content.strip).to eq("T")

    serialized = parsed.to_xml

    # The xmlns declaration must appear on <math>, NOT on <stem>
    expect(serialized).to include('xmlns="http://www.w3.org/1998/Math/MathML"')
    expect(serialized).not_to match(%r{<stem[^>]*xmlns="http://www\.w3\.org/1998/Math/MathML"})
    expect(serialized).to match(%r{<math[^>]*xmlns="http://www\.w3\.org/1998/Math/MathML"})
  end

  it "round-trips with namespace on the correct element" do
    parsed = stem_class.from_xml(input_xml)
    serialized = parsed.to_xml

    # Parse again to verify structural correctness
    reparsed = stem_class.from_xml(serialized)
    expect(reparsed.block).to eq("false")
    expect(reparsed.type).to eq("MathML")
    expect(reparsed.math.content.strip).to eq("T")

    # Second serialization should produce same result as first
    expect(reparsed.to_xml).to be_xml_equivalent_to(serialized)
  end

  context "with nested default namespace that differs from parent" do
    let(:mathml_ns) do
      Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "http://www.w3.org/1998/Math/MathML"
      end
    end

    let(:standoc_ns) do
      Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "https://www.metanorma.org/ns/standoc"
      end
    end

    let(:nested_math_class) do
      ns = mathml_ns
      Class.new do
        include Lutaml::Model::Serialize

        attribute :content, :string

        xml do
          element "math"
          namespace ns
          map_content to: :content
        end

        def self.name
          "NestedMath"
        end
      end
    end

    let(:stem_with_ns_class) do
      ns = standoc_ns
      math = nested_math_class
      Class.new do
        include Lutaml::Model::Serialize

        attribute :block, :string
        attribute :math, math

        xml do
          element "stem"
          namespace ns
          map_attribute "block", to: :block
          map_element "math", to: :math
        end

        def self.name
          "StemWithNs"
        end
      end
    end

    it "preserves distinct namespace declarations on each element" do
      xml = <<~XML
        <stem xmlns="https://www.metanorma.org/ns/standoc" block="false">
          <math xmlns="http://www.w3.org/1998/Math/MathML">µmol</math>
        </stem>
      XML

      serialized = stem_with_ns_class.from_xml(xml).to_xml

      # Each element should have its own xmlns — no hoisting
      expect(serialized).to include('xmlns="https://www.metanorma.org/ns/standoc"')
      expect(serialized).to include('xmlns="http://www.w3.org/1998/Math/MathML"')
      expect(serialized).to include("µmol")

      # stem must NOT carry the MathML namespace
      expect(serialized).not_to match(
        %r{<stem[^>]*xmlns="http://www\.w3\.org/1998/Math/MathML"},
      )
    end
  end
end
