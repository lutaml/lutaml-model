# frozen_string_literal: true

module Lutaml
  module Xml
    module Decisions
      module Rules
        # Priority 4.4: attribute-qualifying namespaces spell prefixed.
        #
        # A namespace that declares attribute_form_default :qualified
        # produces an inherently prefixed document: W3C attributes never
        # inherit the default namespace, so every attribute already
        # carries the prefix, and the coherent spelling prefixes the
        # root too. Namespaces with unqualified attributes (the W3C
        # default) keep the default-xmlns document style.
        #
        # This is the constructed-model counterpart of the parsed path's
        # Priority 1 format preservation: a WordprocessingML-style part
        # (w:document with w:val attributes) serializes prefixed whether
        # it was parsed or built, while a custom-properties-style part
        # (bare fmtid/pid/name attributes) serializes in default-xmlns
        # form in both lanes (lutaml-model#1124).
        #
        # IMPORTANT: This rule does NOT override input format preservation
        # (Priority 1). It only applies when no input format exists
        # (programmatically created models).
        class AttributeQualifiedPrefixRule < DecisionRule
          def priority
            4.4
          end

          def applies?(context)
            return false unless context.has_namespace?

            ns_class = context.namespace_class
            return false unless ns_class
            return false if ns_class.prefix_default.to_s.empty?
            return false unless ns_class.attribute_form_default == :qualified

            # If input format exists, FormatPreservationRule (Priority 1)
            # handles it
            context.preserved_input_format.nil?
          end

          def decide(context)
            ns_class = context.namespace_class
            Decision.prefix(
              prefix: ns_class.prefix_default,
              namespace_class: ns_class,
              reason: "Priority 4.4: attribute_form_default :qualified - " \
                      "inherently prefixed document, root spells prefixed",
            )
          end
        end
      end
    end
  end
end
