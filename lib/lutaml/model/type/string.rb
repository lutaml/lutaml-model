# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class String < Value
        # Performance-optimized cast with short-circuit for already-correct types
        def self.cast(value, options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

          # Short-circuit an already-::String value with no options only when
          # no xs:whiteSpace normalization is requested (the common :string
          # case); a non-preserve mode must fall through to transform the text.
          mode = white_space_mode
          if value.is_a?(::String) && options.equal?(EMPTY_OPTIONS) &&
              mode == :preserve
            return value
          end

          value = value.to_s
          value = value.gsub(/[\t\n\r]/, " ") unless mode == :preserve
          value = value.squeeze(" ").strip if mode == :collapse

          unless options.equal?(EMPTY_OPTIONS)
            Model::Services::Type::Validator::String.validate!(value,
                                                               options)
          end
          value
        end

        # Effective xs:whiteSpace mode for this type, defaulting to :preserve.
        # Memoized per class so the hot cast path avoids re-walking the facet
        # chain; class-instance variables are not inherited, so each subclass
        # computes (and freezes) its own effective mode.
        def self.white_space_mode
          @white_space_mode ||= facets[:white_space] || :preserve
        end

        # Drop the memoized mode when a facet is declared after it was first
        # computed (e.g. a cast before the `white_space` declaration), so the
        # next cast recomputes it from the updated facets.
        def self.reset_facet_cache
          return unless instance_variable_defined?(:@white_space_mode)

          remove_instance_variable(:@white_space_mode)
        end
        private_class_method :reset_facet_cache

        # Default XSD type for String
        #
        # @return [String] xs:string
        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
