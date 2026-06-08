# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Definitions
        # Union type — Lutaml::Model::Type::Value subclass whose cast
        # tries each member type and returns the first that parses.
        # cast_strategy ∈ {:resolve_type, :class_refs}.
        class UnionType
          attr_accessor :class_name, :members, :cast_strategy, :required_files

          def initialize(class_name:, members:, cast_strategy:,
                         required_files: [])
            @class_name = class_name
            @members = members
            @cast_strategy = cast_strategy
            @required_files = required_files
          end
        end
      end
    end
  end
end
