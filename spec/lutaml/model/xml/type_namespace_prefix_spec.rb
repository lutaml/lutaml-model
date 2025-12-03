require "spec_helper"
require "lutaml/model"

RSpec.describe "Type Namespace Prefix Issue #6" do
  # Define MathML namespace for testing
  class MathMLNamespace < Lutaml::Model::XmlNamespace
    uri "http://www.w3.org/1998/Math/MathML"
    prefix_default "mml"
  end

  # Define a type with namespace
  class MathMLType < Lutaml::Model::Type::String
    xml_namespace MathMLNamespace
  end

  context "elements with type namespaces" do
    it "preserves namespace prefix on typed elements during serialization" do
      # Create a model with a typed attribute
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :math_content, MathMLType

        xml do
          root "article"
          map_element "math", to: :math_content
        end
      end

      # Create instance and serialize
      instance = test_class.new(math_content: "<apply><plus/></apply>")
      xml_output = instance.to_xml
      
      # The element should have the mml prefix from the type's namespace
      expect(xml_output).to include("<mml:math>")
      expect(xml_output).to include("</mml:math>")
      expect(xml_output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
    end

    it "maintains type namespace prefix through round-trip" do
      xml_input = <<~XML
        <article xmlns:mml="http://www.w3.org/1998/Math/MathML">
          <mml:math><apply><plus/></apply></mml:math>
        </article>
      XML

      # Parse
      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      
      # Re-serialize
      output = doc.to_xml
      
      # Verify prefix is preserved
      expect(output).to include('<mml:math>')
      expect(output).to include('</mml:math>')
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
    end
  end

  context "nested types with namespaces" do
    # Define nested namespace for testing
    class SpecialNamespace < Lutaml::Model::XmlNamespace
      uri "http://example.com/special"
      prefix_default "spec"
    end

    class SpecialType < Lutaml::Model::Type::String
      xml_namespace SpecialNamespace
    end

    it "preserves prefixes for nested model types" do
      inner_class = Class.new(Lutaml::Model::Serializable) do
        attribute :special_content, SpecialType

        xml do
          root "inner"
          namespace SpecialNamespace
          map_element "content", to: :special_content
        end
      end

      outer_class = Class.new(Lutaml::Model::Serializable) do
        attribute :inner, inner_class

        xml do
          root "outer"
          map_element "inner", to: :inner
        end
      end

      instance = outer_class.new(
        inner: inner_class.new(special_content: "test")
      )
      
      xml_output = instance.to_xml
      
      # Both inner element and its content should have spec prefix
      expect(xml_output).to include("<spec:inner>")
      expect(xml_output).to include("</spec:inner>")
      expect(xml_output).to include('xmlns:spec="http://example.com/special"')
    end
  end

  context "collections with typed elements" do
    it "maintains prefixes for collections of typed elements" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :math_items, MathMLType, collection: true

        xml do
          root "article"
          map_element "math", to: :math_items
        end
      end

      instance = test_class.new(
        math_items: ["<expr>x+y</expr>", "<expr>a*b</expr>"]
      )
      
      xml_output = instance.to_xml
      
      # All math elements should have mml prefix
      expect(xml_output.scan(/<mml:math>/).count).to eq(2)
      expect(xml_output.scan(/<\/mml:math>/).count).to eq(2)
      expect(xml_output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
    end
  end

  context "real-world MathML example" do
    it "preserves MathML namespace prefix in JATS article" do
      xml_input = <<~XML
        <article xmlns:mml="http://www.w3.org/1998/Math/MathML">
          <body>
            <p>The equation 
              <mml:math>
                <mml:mrow>
                  <mml:mi>E</mml:mi>
                  <mml:mo>=</mml:mo>
                  <mml:mi>m</mml:mi>
                  <mml:msup>
                    <mml:mi>c</mml:mi>
                    <mml:mn>2</mml:mn>
                  </mml:msup>
                </mml:mrow>
              </mml:math>
              is famous.
            </p>
          </body>
        </article>
      XML

      doc = Lutaml::Model::Xml::NokogiriAdapter.parse(xml_input)
      output = doc.to_xml
      
      # Verify all MathML elements retain their prefix
      expect(output).to include('<mml:math>')
      expect(output).to include('<mml:mrow>')
      expect(output).to include('<mml:mi>')
      expect(output).to include('<mml:mo>')
      expect(output).to include('<mml:msup>')
      expect(output).to include('<mml:mn>')
      
      # Verify namespace declaration is present
      expect(output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
    end
  end

  context "mixed content with type namespaces" do
    it "preserves type namespace prefixes in mixed content" do
      # Define link namespace
      class XLinkNamespace < Lutaml::Model::XmlNamespace
        uri "http://www.w3.org/1999/xlink"
        prefix_default "xlink"
      end

      class XLinkType < Lutaml::Model::Type::String
        xml_namespace XLinkNamespace
      end

      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :href, XLinkType
        attribute :text, :string

        xml do
          root "link"
          map_attribute "href", to: :href
          map_content to: :text
        end
      end

      instance = test_class.new(href: "http://example.com", text: "Click here")
      xml_output = instance.to_xml
      
      # xlink:href attribute should have prefix
      expect(xml_output).to include('xlink:href="http://example.com"')
      expect(xml_output).to include('xmlns:xlink="http://www.w3.org/1999/xlink"')
    end
  end

  context "namespace collector integration" do
    it "NamespaceCollector captures type namespaces correctly" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :math, MathMLType

        xml do
          root "doc"
          map_element "math", to: :math
        end
      end

      mapping = test_class.mappings_for(:xml)
      collector = Lutaml::Model::Xml::NamespaceCollector.new
      needs = collector.collect(nil, mapping, mapper_class: test_class)
      
      # Verify type namespace is captured
      expect(needs[:type_namespaces]).to include(:math)
      expect(needs[:type_namespaces][:math]).to eq(MathMLNamespace)
      
      # Verify it's in the namespaces collection
      key = MathMLNamespace.to_key
      expect(needs[:namespaces]).to have_key(key)
      expect(needs[:namespaces][key][:ns_object]).to eq(MathMLNamespace)
    end
  end

  context "declaration planner integration" do
    it "DeclarationPlanner includes type namespaces in plan with prefix format" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :math, MathMLType

        xml do
          root "doc"
          map_element "math", to: :math
        end
      end

      mapping = test_class.mappings_for(:xml)
      collector = Lutaml::Model::Xml::NamespaceCollector.new
      needs = collector.collect(nil, mapping, mapper_class: test_class)
      
      planner = Lutaml::Model::Xml::DeclarationPlanner.new
      plan = planner.plan(nil, mapping, needs, options: { mapper_class: test_class })
      
      # Verify type namespace is in plan
      expect(plan[:type_namespaces]).to include(:math)
      expect(plan[:type_namespaces][:math]).to eq(MathMLNamespace)
      
      # Verify namespace is in main plan with prefix format
      key = MathMLNamespace.to_key
      expect(plan[:namespaces]).to have_key(key)
      expect(plan[:namespaces][key][:format]).to eq(:prefix)
      expect(plan[:namespaces][key][:ns_object]).to eq(MathMLNamespace)
    end
  end

  context "edge cases" do
    it "handles type namespace when element has explicit namespace override" do
      # Type has one namespace, but element explicitly uses different namespace
      class DefaultNamespace < Lutaml::Model::XmlNamespace
        uri "http://example.com/default"
        prefix_default "def"
      end

      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :content, MathMLType

        xml do
          root "doc"
          # Explicit namespace override
          map_element "content", to: :content, namespace: DefaultNamespace
        end
      end

      instance = test_class.new(content: "test")
      xml_output = instance.to_xml
      
      # Should use explicit namespace, not type namespace
      expect(xml_output).to include('xmlns:def="http://example.com/default"')
      expect(xml_output).to include("<def:content>")
    end

    it "handles type without namespace (regular type)" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :simple, :string

        xml do
          root "doc"
          map_element "simple", to: :simple
        end
      end

      instance = test_class.new(simple: "text")
      xml_output = instance.to_xml
      
      # Should not have any namespace prefix
      expect(xml_output).to include("<simple>")
      expect(xml_output).not_to include(":")
    end
  end

  context "multiple type namespaces" do
    # Define another namespace for testing
    class SVGNamespace < Lutaml::Model::XmlNamespace
      uri "http://www.w3.org/2000/svg"
      prefix_default "svg"
    end

    class SVGType < Lutaml::Model::Type::String
      xml_namespace SVGNamespace
    end

    it "handles multiple different type namespaces in same document" do
      test_class = Class.new(Lutaml::Model::Serializable) do
        attribute :math, MathMLType
        attribute :graphic, SVGType

        xml do
          root "article"
          map_element "math", to: :math
          map_element "graphic", to: :graphic
        end
      end

      instance = test_class.new(
        math: "<expr>x+y</expr>",
        graphic: "<circle/>"
      )
      
      xml_output = instance.to_xml
      
      # Both namespaces should be declared and used
      expect(xml_output).to include('xmlns:mml="http://www.w3.org/1998/Math/MathML"')
      expect(xml_output).to include('xmlns:svg="http://www.w3.org/2000/svg"')
      expect(xml_output).to include("<mml:math>")
      expect(xml_output).to include("<svg:graphic>")
    end
  end
end