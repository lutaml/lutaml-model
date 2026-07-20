# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # An XML namespace declaration (subclass of
        # Lutaml::Xml::W3c::XmlNamespace).
        class Namespace
          attr_accessor :class_name, :uri, :prefix_default, :element_form_default

          def initialize(class_name:, uri:, prefix_default: nil,
                         element_form_default: nil)
            @class_name = class_name
            @uri = uri
            @prefix_default = prefix_default
            @element_form_default = element_form_default
          end
        end
      end
    end
  end
end
