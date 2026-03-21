# frozen_string_literal: true

# lib/lutaml/model/xml/decisions/rules/element_form_default_unqualified_rule.rb
module Lutaml
  module Xml
    module Decisions
      module Rules
        # Priority 0.45: Element form default unqualified
        #
        # When namespace has element_form_default :unqualified, local elements should
        # NOT be namespace-qualified in the instance document. This means:
        # - If parent uses prefix format: child should have no xmlns attribute (blank namespace)
        # - If parent uses default format: child should have xmlns="" (explicit blank)
        #
        # This rule runs AFTER InheritFromParentRule (Priority 0) but BEFORE
        # HoistedOnParentRule (Priority 0.5), ensuring that element_form_default
        # takes precedence over parent's hoisting decisions.
        #
        # W3C COMPLIANCE:
        # elementFormDefault="unqualified" means local elements appear without
        # namespace prefix in instance documents.
        #
        # Example:
        # Schema: elementFormDefault="unqualified"
        # Instance: <gc:CodeList xmlns:gc="uri"><Identification><ShortName>...</ShortName></Identification></gc:CodeList>
        # Note: child elements have NO xmlns attribute (blank namespace)
        class ElementFormDefaultUnqualifiedRule < DecisionRule
          # Priority 0.45 (between InheritFromParentRule 0 and HoistedOnParentRule 0.5)
          def priority
            0.45
          end

          # Applies when:
          # 1. Element has a namespace
          # 2. Namespace has element_form_default EXPLICITLY set to :unqualified
          # 3. Parent uses prefix format (otherwise InheritFromParentRule handles it)
          def applies?(context)
            return false unless context.has_namespace?

            ns_class = context.namespace_class
            return false unless ns_class

            # Check if namespace has element_form_default EXPLICITLY set to :unqualified
            # CRITICAL: Only applies when explicitly set, not when defaulted to :unqualified
            return false unless ns_class.element_form_default_set?
            return false unless ns_class.element_form_default == :unqualified

            # This rule only applies when parent uses prefix format
            # If parent uses default format, InheritFromParentRule handles it
            return false unless context.parent_format == :prefix

            # Only apply if no explicit form option on the element
            # ElementFormOptionRule (Priority -0.5) handles explicit form options
            return false if context.element.respond_to?(:form) && !context.element.form.nil?

            true
          end

          # Decision: Blank namespace (no xmlns attribute)
          # When parent uses prefix format, child should be in blank namespace
          # to opt out of inheriting any namespace. This results in no xmlns
          # attribute on the child element.
          def decide(context)
            Decision.blank(
              namespace_class: context.namespace_class,
              reason: "Priority 0.45: element_form_default :unqualified - blank namespace (no xmlns)",
            )
          end
        end
      end
    end
  end
end
