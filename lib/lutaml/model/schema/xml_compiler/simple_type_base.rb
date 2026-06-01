# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # Mixin holding the override behavior shared by every XSD
        # simple-type renderer (RestrictedSimpleType and UnionSimpleType):
        #
        #   - `class_name` attr (raw input name, e.g. `"st_color"` or
        #     `"StIntegerRange"`)
        #   - `rendered_class_name` memoizes the CamelCase form
        #   - both use `@register ||=` memoization
        #   - both keep `register` even when inside a module namespace, so
        #     union resolution can call `register.get_class`
        module SimpleTypeBase
          def self.included(base)
            base.attr_accessor(:class_name)
          end

          def rendered_class_name
            @rendered_class_name ||= Utils.camel_case(class_name)
          end

          def registration_lazy?
            true
          end

          def keep_register_when_namespaced?
            true
          end
        end
      end
    end
  end
end
