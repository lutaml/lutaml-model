# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # Union type — Lutaml::Model::Type::Value subclass whose cast
        # tries each member type and returns the first that parses.
        # cast_strategy ∈ {:resolve_type, :class_refs}.
        class UnionType
          attr_accessor :class_name, :members, :cast_strategy, :required_files,
                        :lazy_register, :keep_register_when_namespaced

          def initialize(class_name:, members:, cast_strategy:,
                         required_files: [], lazy_register: false,
                         keep_register_when_namespaced: false)
            @class_name = class_name
            @members = members
            @cast_strategy = cast_strategy
            @required_files = required_files
            @lazy_register = lazy_register
            @keep_register_when_namespaced = keep_register_when_namespaced
          end
        end
      end
    end
  end
end
