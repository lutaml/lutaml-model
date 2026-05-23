# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Pure value object holding the output of compilation.
        # No I/O — just data. The FileWriter / ClassLoader collaborators
        # consume this to perform the impure parts of `to_models`.
        class CompiledOutput
          attr_reader :classes, :sources, :module_namespace, :register_id

          def initialize(classes:, sources:, module_namespace: nil,
                         register_id: :default)
            @classes = classes
            @sources = sources
            @module_namespace = module_namespace
            @register_id = register_id
          end
        end
      end
    end
  end
end
