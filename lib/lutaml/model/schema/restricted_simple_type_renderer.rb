# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Base class for any renderer that emits a *restricted* simple-type
      # subclass — a `class X < Lutaml::Model::Type::Integer` (etc.) with
      # a `def self.cast` body that mutates `options` with facet values
      # then delegates to super.
      #
      # Inherited by:
      #   - Lutaml::Model::Schema::XmlCompiler::SimpleType (non-union path)
      #   - Lutaml::Model::Schema::RngCompiler::SimpleType
      class RestrictedSimpleTypeRenderer
        include ClassBoilerplate

        def template
          Templates::RESTRICTED_SIMPLE_TYPE
        end

        # ----------------------------------------------------------------
        # Hook contract for Templates::RESTRICTED_SIMPLE_TYPE.
        # Children override what's specific.
        # ----------------------------------------------------------------

        def rendered_class_name
          raise NotImplementedError, "#{self.class} must implement #rendered_class_name"
        end

        # The base class to extend, e.g. "Lutaml::Model::Type::Integer".
        # nil means no `< Parent` clause is emitted.
        def parent_class
          nil
        end

        # `require_relative` / `require` lines under top-level require.
        def restricted_simple_type_required_files
          ""
        end

        # Facet-application lines inside `def self.cast` (between
        # `return if value.nil?` and `value = super`).
        def restricted_simple_type_cast_body
          ""
        end
      end
    end
  end
end
