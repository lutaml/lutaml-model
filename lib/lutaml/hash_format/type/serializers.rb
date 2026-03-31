# frozen_string_literal: true

module Lutaml
  module HashFormat
    module Type
      # Registers Hash-format-specific type serializers for types that need
      # custom to_hash / from_hash behavior beyond the default.
      module Serializers
        module_function

        def register_all!
          v = Lutaml::Model::Type::Value

          # Reference — key for to_hash, cast for from_hash
          v.register_format_type_serializer(
            :hash, Lutaml::Model::Type::Reference,
            to: ->(inst) { inst.key },
            from: ->(val) { Lutaml::Model::Type::Reference.cast(val) }
          )
        end
      end
    end
  end
end
