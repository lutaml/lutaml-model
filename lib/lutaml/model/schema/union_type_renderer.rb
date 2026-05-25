# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Base class for any renderer that emits a Lutaml::Model::Type::Value
      # subclass representing a union of multiple member types.
      #
      # The cast-body strategy is the only thing that differs between
      # formats: XSD uses `||`-chained `Lutaml::Model::GlobalContext.resolve_type`
      # lookups against the register; RNG uses an each-loop with rescue
      # over the resolved class references. Children override
      # `union_cast_body` to supply their strategy.
      #
      # Inherited by:
      #   - Lutaml::Model::Schema::RngCompiler::UnionType
      #   (XSD union path lives inside XmlCompiler::SimpleType for now —
      #    it dispatches there because XSD's SimpleType class doubles as
      #    a restricted-type renderer too.)
      class UnionTypeRenderer
        include ClassBoilerplate

        def template
          Templates::UNION_TYPE
        end

        # ----------------------------------------------------------------
        # Hook contract.
        # ----------------------------------------------------------------

        def rendered_class_name
          raise NotImplementedError, "#{self.class} must implement #rendered_class_name"
        end

        # Lines emitted ABOVE the module wrap (extra requires). May be "".
        def union_required_files
          ""
        end

        # The cast-body — lines between `return if value.nil?` and `end`.
        # Must end with a newline.
        def union_cast_body
          raise NotImplementedError, "#{self.class} must implement #union_cast_body"
        end
      end
    end
  end
end
