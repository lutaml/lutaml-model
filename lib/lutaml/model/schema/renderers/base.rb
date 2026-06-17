# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module Renderers
        # Shared constructor and helpers for the value/namespace renderers
        # (Union, RestrictedType, Namespace). Model has its own constructor
        # because it computes an opt-out (module-wrappable) namespace.
        class Base
          def self.render(spec, **)
            new(spec, **).render
          end

          def initialize(spec, indent: 2, module_namespace: nil, register_id: :default)
            @spec = spec
            @indent = indent.is_a?(Integer) ? " " * indent : indent
            @extended_indent = @indent * 2
            @module_namespace = module_namespace
            @modules = module_namespace&.split("::") || []
            @register_id = register_id
          end

          private

          def required_files_block
            files = @spec.required_files
            files.empty? ? "" : "#{files.uniq.join("\n")}\n"
          end

          def module_opening = ModuleNesting.opening(@modules)
          def module_closing = ModuleNesting.closing(@modules)
          def boilerplate_indent_str = @indent
        end
      end
    end
  end
end
