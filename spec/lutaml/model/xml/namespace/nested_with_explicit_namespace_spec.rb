require "spec_helper"
require_relative "../../../../support/xml_mapping_namespaces"

# <Base xmlns:test="https://test-namespace">
#   <test:Element1>
#     <test:Element>Value</test:Element>
#     <ElementWithoutNamespace>
#       <NestedElementWithoutNamespace>
#         Value for nested element without namespace
#       </NestedElementWithoutNamespace>
#     </ElementWithoutNamespace>
#   </test:Element1>
# </Base>

module NestedWithExplicitNamespaceSpec
  class NestedElementWithoutNamespace < Lutaml::Model::Serializable
    attribute :nested_element_without_namespace, :string

    xml do
      map_element "NestedElementWithoutNamespace",
                  to: :nested_element_without_namespace
    end
  end

  class ElementWithoutNamespace < Lutaml::Model::Serializable
    attribute :nested_element_without_namespace, :string

    xml do
      map_element "NestedElementWithoutNamespace",
                  to: :nested_element_without_namespace
    end
  end

  class Element1 < Lutaml::Model::Serializable
    attribute :element, :string
    attribute :element_without_namespace, ElementWithoutNamespace

    xml do
      map_element "Element", to: :element
      map_element "ElementWithoutNamespace", to: :element_without_namespace,
                                             namespace: nil
    end
  end

  class Base < Lutaml::Model::Serializable
    attribute :element1, Element1

    xml do
      element "Base"
      namespace TestBaseNamespace

      map_element "Element1", to: :element1
    end
  end
end

RSpec.describe "NestedWithExplicitNamespace" do
  let(:xml) do
    <<~XML
      <Base xmlns:test="https://test-namespace">
        <test:Element1>
          <test:Element>Value</test:Element>
          <ElementWithoutNamespace>
            <NestedElementWithoutNamespace>
              Value for nested element without namespace
            </NestedElementWithoutNamespace>
          </ElementWithoutNamespace>
        </test:Element1>
      </Base>
    XML
  end

  let(:parsed) { NestedWithExplicitNamespaceSpec::Base.from_xml(xml) }

  it "parses namespaced element correctly" do
    expect(parsed.element1.element).to eq("Value")
  end

  it "parses nested element without namespace correclty" do
    generated_value = parsed.element1
      .element_without_namespace
      .nested_element_without_namespace
      .strip

    expect(generated_value).to eq("Value for nested element without namespace")
  end
end
