# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Shared `type_symbol` implementation for renderers whose registry
        # symbol is the snake_case of their generated class name. Mixed
        # into SimpleType, UnionType, and Namespace — all expose
        # `class_name` and register under that symbol.
        module TypeSymbol
          def type_symbol
            Utils.snake_case(class_name).to_sym
          end
        end
      end
    end
  end
end
