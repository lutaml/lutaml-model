# frozen_string_literal: true

require "erb"
require_relative "../templates"
require_relative "../module_nesting"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Renders a Definitions::Namespace into a
        # Lutaml::Xml::W3c::XmlNamespace subclass.
        class Namespace
          def self.render(spec, **options)
            new(spec, **options).render
          end

          def initialize(spec, indent: 2, module_namespace: nil, register_id: :default)
            @spec = spec
            @indent = indent.is_a?(Integer) ? " " * indent : indent
            @module_namespace = module_namespace
            @modules = module_namespace&.split("::") || []
            @register_id = register_id
          end

          def render
            Templates::XML_NAMESPACE.result(binding)
          end

          private

          def class_name = @spec.class_name
          def uri = @spec.uri
          def prefix_default = @spec.prefix_default

          def module_opening = ModuleNesting.opening(@modules)
          def module_closing = ModuleNesting.closing(@modules)
        end
      end
    end
  end
end
