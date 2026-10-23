# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Pattern machinery shared by the NIST Metaschema string types (#107).
      # Each including class defines a PATTERN regexp; values cast to
      # strings and validate full-match against it.
      module MetaschemaPattern
        def pattern
          self::PATTERN
        end

        def valid?(value)
          return false if value.nil?

          pattern.match?(value.to_s)
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
