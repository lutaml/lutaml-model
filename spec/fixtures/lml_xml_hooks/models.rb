# frozen_string_literal: true

require "lutaml/model"
require "lutaml/xml"

# XML models with hand-written `with:` callbacks (content, element, attribute
# rules), shaped like Unitsml::Model::Units::Symbol. `calls` records every
# source callback that runs: export and import must leave it empty.
module LmlXmlHookFixtures
  def self.calls
    @calls ||= []
  end

  class Ns < Lutaml::Xml::Namespace
    uri "urn:lml:xmlhooks"
    prefix_default "h"
  end

  # The same shape as Unitsml::Model::Units::Symbol (map_content with callbacks).
  class SymbolLike < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :content, :string

    xml do
      element "UnitSymbol"
      namespace Ns

      map_attribute :type, to: :type
      map_content to: :content, with: { from: :content_from_xml, to: :content_to_xml }
    end

    def content_from_xml(_model, _value)
      LmlXmlHookFixtures.calls << :content_from
    end

    def content_to_xml(model, parent, doc)
      LmlXmlHookFixtures.calls << :content_to
      doc.add_xml_fragment(parent, model.content)
    end
  end

  # Ordinary XML, no hooks.
  class Regular < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :tag, :string

    xml do
      element "regular"
      namespace Ns
      map_attribute "name", to: :name
      map_element "tag", to: :tag
    end
  end

  # A named element rule with callbacks and a hook-only one.
  class Mixed < Lutaml::Model::Serializable
    attribute :title, :string
    attribute :body, :string

    xml do
      element "mixedHooks"
      namespace Ns
      map_element "title", to: :title, with: { from: :title_from_xml, to: :title_to_xml }
      map_element "extra", with: { from: :extra_from_xml, to: :extra_to_xml }
    end

    def title_from_xml(_model, _value)
      LmlXmlHookFixtures.calls << :title_from
    end

    def title_to_xml(_model, _parent, _doc)
      LmlXmlHookFixtures.calls << :title_to
    end

    def extra_from_xml(_model, _value)
      LmlXmlHookFixtures.calls << :extra_from
    end

    def extra_to_xml(_model, _parent, _doc)
      LmlXmlHookFixtures.calls << :extra_to
    end
  end

  # Order driven by a callback: the refusal must stay.
  class CallbackOrdered < Lutaml::Model::Serializable
    attribute :x, :string

    xml do
      element "ordered"
      ordered
      map_element "x", to: :x, with: { from: :x_from, to: :x_to }
    end

    def x_from(_model, _value); end

    def x_to(_model, _parent, _doc); end
  end

  class KvAndXml < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      element "kvAndXml"
      map_element "name", to: :name, with: { from: :shared_from, to: :shared_to }
    end

    key_value do
      map "name", to: :name, with: { from: :shared_from, to: :shared_to }
    end

    def shared_from(_model, _value); end

    def shared_to(_model, _doc); end
  end
end
