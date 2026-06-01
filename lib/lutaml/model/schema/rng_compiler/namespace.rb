# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # RNG namespace class — inherits the full render flow from
        # Lutaml::Model::Schema::NamespaceRenderer. Adds an RNG-specific
        # type_symbol method and `fragment` marker used by the compiler.
        class Namespace < Lutaml::Model::Schema::NamespaceRenderer
          attr_reader :fragment

          def initialize(uri:, prefix: nil, class_name: nil)
            super
            @fragment = true
          end

          def type_symbol
            Utils.snake_case(class_name).to_sym
          end

          # RNG calls renderers via #render(kwargs); NamespaceRenderer's
          # entry point is to_class(options: hash) — bridge here.
          def render(indent: 2, module_namespace: nil, register_id: :default)
            _ = indent
            _ = register_id
            to_class(options: { module_namespace: module_namespace })
          end
        end
      end
    end
  end
end
