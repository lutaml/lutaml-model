# frozen_string_literal: true

require "lutaml/model"

# Named fixtures for LML ordered-content capture/apply specs. The LML
# document addresses models by class path, so they must be nameable.
module LmlOrderFixtures
  class NsA < Lutaml::Xml::Namespace
    uri "urn:lml-order:a"
    prefix_default "a"
  end

  class NsB < Lutaml::Xml::Namespace
    uri "urn:lml-order:b"
    prefix_default "b"
  end

  class Emphasis < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "em"
      map_content to: :value
    end
  end

  # Mixed content: repeated interleaved elements, text and CDATA.
  class Para < Lutaml::Model::Serializable
    attribute :em, Emphasis, collection: true
    attribute :bold, :string, collection: true
    attribute :note, :string
    attribute :text, :string, collection: true

    xml do
      element "p"
      mixed_content
      map_element "em", to: :em
      map_element "b", to: :bold
      map_element "note", to: :note
      map_content to: :text
    end
  end

  # Element-only `ordered` model with repeated interleaved elements.
  class Transport < Lutaml::Model::Serializable
    attribute :car, :string, collection: true
    attribute :boat, :string, collection: true

    xml do
      element "transportation"
      ordered
      map_element "car", to: :car
      map_element "boat", to: :boat
    end
  end

  class ItemA < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "item"
      namespace NsA
      map_content to: :value
    end
  end

  class ItemB < Lutaml::Model::Serializable
    attribute :value, :string

    xml do
      element "item"
      namespace NsB
      map_content to: :value
    end
  end

  # Two same-named elements told apart only by namespace.
  class Namespaced < Lutaml::Model::Serializable
    attribute :a_items, ItemA, collection: true
    attribute :b_items, ItemB, collection: true

    xml do
      element "root"
      namespace NsA
      ordered
      map_element "item", to: :a_items
      map_element "item", to: :b_items
    end
  end

  # An element member whose output is produced by a custom method.
  class ImperativeRule < Lutaml::Model::Serializable
    attribute :car, :string, collection: true

    xml do
      element "imperative"
      ordered
      map_element "car", to: :car, with: { to: :car_to_xml, from: :car_from_xml }
    end

    def car_to_xml(_model, _parent, _doc); end

    def car_from_xml(model, value)
      model.car = Array(value)
    end
  end

  # A class that generates its own element order.
  class ImperativeOrder < Lutaml::Model::Serializable
    attribute :car, :string, collection: true

    xml do
      element "imperative"
      ordered
      map_element "car", to: :car
    end

    def element_order
      Array(car).map { |_| Lutaml::Xml::Element.new("Element", "car") }
    end
  end

  class ReservedMember < Lutaml::Model::Serializable
    attribute :__lml_content, :string, collection: true
    attribute :car, :string

    xml do
      element "reserved"
      ordered
      map_element "car", to: :car
    end
  end

  # No per-instance order at all.
  class Plain < Lutaml::Model::Serializable
    attribute :car, :string

    xml do
      element "plain"
      map_element "car", to: :car
    end
  end

  PARA_XML = "<p>hi <em>a</em> mid <![CDATA[cd]]> <b>x</b><em>b</em> " \
             "<note>n</note> tail</p>"
  TRANSPORT_XML = "<transportation><car>1</car><boat>2</boat><car>3</car>" \
                  "<boat>4</boat><car>5</car></transportation>"
  NAMESPACED_XML = '<a:root xmlns:a="urn:lml-order:a" xmlns:b="urn:lml-order:b">' \
                   "<a:item>1</a:item><b:item>2</b:item><a:item>3</a:item>" \
                   "<b:item>4</b:item></a:root>"
end
