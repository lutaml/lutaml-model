# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Pattern machinery shared by the NIST Metaschema string types (#107).
      # Each including class defines a PATTERN regexp (also declared as the
      # type's `pattern` facet, feeding runtime validation and XSD
      # restriction emission); values cast to strings and `valid?` checks
      # full-match against it.
      module MetaschemaPattern
        def valid?(value)
          return false if value.nil?

          self::PATTERN.match?(value.to_s)
        end

        def cast(value, _options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)
          return value if value.is_a?(::String)

          value.to_s
        end

        def serialize(value)
          return nil if value.nil?

          value.to_s
        end
      end
    end
  end
end
