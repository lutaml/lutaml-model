# frozen_string_literal: true

require "lutaml/model"
require "lutaml/xml"

# Models whose XML rules take their namespace from different static
# declarations, for lml_effective_namespace_spec.
module LmlEffectiveNamespaceFixtures
  class HostNs < Lutaml::Xml::Namespace
    uri "urn:lml:host"
    prefix_default "h"
  end

  class QualifiedNs < Lutaml::Xml::Namespace
    uri "urn:lml:qualified"
    prefix_default "q"
    element_form_default :qualified
  end

  class AttrQualifiedNs < Lutaml::Xml::Namespace
    uri "urn:lml:attrq"
    prefix_default "a"
    attribute_form_default :qualified
  end

  class OtherNs < Lutaml::Xml::Namespace
    uri "urn:lml:other"
    prefix_default "o"
  end

  # A String type that belongs to its own XML namespace (as XmlIdType does).
  class OtherNsType < Lutaml::Model::Type::String
    xml do
      namespace OtherNs
    end
  end

  class Leaf < Lutaml::Model::Serializable
    attribute :v, :string

    xml do
      element "leaf"
      namespace HostNs
      map_element "v", to: :v
    end
  end

  class Host < Lutaml::Model::Serializable
    attribute :plain, :string
    attribute :forced, :string
    attribute :opted_out, :string
    attribute :flat, :string
    attribute :typed_element, OtherNsType
    attribute :typed_attribute, OtherNsType
    attribute :xml_id, Lutaml::Xml::W3c::XmlIdType
    attribute :plain_attribute, :string
    attribute :leaf, Leaf

    xml do
      element "host"
      namespace HostNs
      map_element "plain", to: :plain
      map_element "forced", to: :forced, form: :qualified
      map_element "optedOut", to: :opted_out, namespace: nil
      map_element "flat", to: :flat, form: :unqualified
      map_element "typedElement", to: :typed_element
      map_attribute "typedAttribute", to: :typed_attribute
      map_attribute "id", to: :xml_id
      map_attribute "plainAttribute", to: :plain_attribute
      map_element "leaf", to: :leaf
    end
  end

  class QualifiedHost < Lutaml::Model::Serializable
    attribute :plain, :string
    attribute :flat, :string
    attribute :attr, :string

    xml do
      element "qualifiedHost"
      namespace QualifiedNs
      map_element "plain", to: :plain
      map_element "flat", to: :flat, form: :unqualified
      map_attribute "attr", to: :attr
    end
  end

  class AttrQualifiedHost < Lutaml::Model::Serializable
    attribute :plain, :string
    attribute :attr, :string

    xml do
      element "attrQualifiedHost"
      namespace AttrQualifiedNs
      map_element "plain", to: :plain
      map_attribute "attr", to: :attr
    end
  end

  class NoNamespace < Lutaml::Model::Serializable
    attribute :plain, :string
    attribute :attr, :string

    xml do
      element "noNamespace"
      map_element "plain", to: :plain
      map_attribute "attr", to: :attr
    end
  end

  SAMPLES = {
    Host => lambda {
      Host.new(plain: "p", forced: "f", opted_out: "o", flat: "u", typed_element: "te",
               typed_attribute: "ta", xml_id: "id1", plain_attribute: "pa",
               leaf: Leaf.new(v: "x"))
    },
    QualifiedHost => -> { QualifiedHost.new(plain: "p", flat: "f", attr: "a") },
    AttrQualifiedHost => -> { AttrQualifiedHost.new(plain: "p", attr: "a") },
    NoNamespace => -> { NoNamespace.new(plain: "p", attr: "a") },
  }.freeze
end
