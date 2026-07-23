# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders a Definitions::Namespace into a
        # Lutaml::Xml::W3c::XmlNamespace subclass.
        class Namespace < Base
          def render
            Templates::XML_NAMESPACE.result(binding)
          end

          private

          def class_name = @spec.class_name
          def uri = @spec.uri
          def prefix_default = @spec.prefix_default

          def element_form_default_line
            efd = @spec.element_form_default
            efd && "element_form_default #{efd.inspect}"
          end
        end
      end
    end
  end
end
