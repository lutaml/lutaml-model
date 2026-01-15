# frozen_string_literal: true
# lib/lutaml/model/xml/decisions/rules/namespace_scope_rule.rb
require_relative '../decision_rule'

module Lutaml
  module Model
    module Xml
      module Decisions
        module Rules
          # Priority 3: namespace_scope configuration
          #
          # When namespace_scope hoists a namespace to root, elements using
          # that namespace MUST use prefix format (UNLESS it's the ROOT
          # element's OWN namespace - in which case default format is preferred)
          class NamespaceScopeRule < DecisionRule
            # Priority 3
            def priority
              3
            end

            # Applies when namespace is in namespace_scope configuration AND will be hoisted
            def applies?(context)
              return false unless context.has_namespace?
              config = context.namespace_scope_config
              return false if config.nil?

              # Only apply if namespace_scope will actually hoist
              ns_usage = context.namespace_usage
              config.always_mode? || (config.auto_mode? && ns_usage&.used_in&.any?)
            end

            # Decision: Use prefix (except for root's own namespace)
            def decide(context)
              scope_config = context.namespace_scope_config

              if context.is_root && context.has_namespace?
                # Root element with its own namespace -> use default format (cleaner)
                Decision.default(
                  namespace_class: context.namespace_class,
                  reason: "Priority 3: Root element's own namespace - use default format"
                )
              else
                # Other hoisted namespaces OR non-root elements -> MUST use prefix
                Decision.prefix(
                  prefix: context.namespace_class.prefix_default,
                  namespace_class: context.namespace_class,
                  reason: "Priority 3: namespace_scope hoisting - use prefix format"
                )
              end
            end
          end
        end
      end
    end
  end
end
