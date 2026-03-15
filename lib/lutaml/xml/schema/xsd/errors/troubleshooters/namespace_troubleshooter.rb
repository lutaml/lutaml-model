# frozen_string_literal: true

require_relative "troubleshooting_handler"

module Lutaml
  module Xml
    module Schema
      module Xsd
        module Errors
          module Troubleshooters
            # Troubleshooter for namespace-related errors
            #
            # Provides tips for resolving namespace issues
            #
            # @example Using the troubleshooter
            #   class NamespaceError < EnhancedError
            #     use_troubleshooter NamespaceTroubleshooter
            #   end
            #
            #   error = NamespaceError.new(
            #     "Namespace prefix 'gml' not found",
            #     context: {
            #       namespace: "http://www.opengis.net/gml/3.2",
            #       actual_value: "gml:CodeType"
            #     }
            #   )
            #   error.troubleshooting_tips # => ["Check if namespace prefix...", ...]
            class NamespaceTroubleshooter < TroubleshootingHandler
              # Generate namespace troubleshooting tips
              #
              # @param error [EnhancedError] The error
              # @return [Array<String>] Troubleshooting tips
              def tips_for(error)
                return [] unless can_troubleshoot?(error)

                tips = []
                context = context_from(error)

                tips.concat(namespace_uri_tips(context)) if context.namespace

                tips.concat(namespace_prefix_tips(context)) if context.actual_value&.include?(":")

                tips.concat(general_namespace_tips)
                tips
              end

              private

              # Tips for namespace URI issues
              #
              # @param context [ErrorContext] Error context
              # @return [Array<String>] Tips
              def namespace_uri_tips(context)
                [
                  "Verify namespace URI is correct: #{context.namespace}",
                  "Check if the namespace is registered in your schema package",
                ]
              end

              # Tips for namespace prefix issues
              #
              # @param context [ErrorContext] Error context
              # @return [Array<String>] Tips
              def namespace_prefix_tips(context)
                prefix = extract_prefix(context.actual_value)
                [
                  "Check if namespace prefix '#{prefix}' is registered",
                  "Verify the prefix mapping in your schema configuration",
                ]
              end

              # General namespace troubleshooting tips
              #
              # @return [Array<String>] Tips
              def general_namespace_tips
                [
                  "List available namespaces: lutaml-xsd namespace list --from package.lxr",
                  "Check namespace configuration in config/namespace_mapping.yml",
                  "Ensure all required schemas are imported",
                ]
              end

              # Extract namespace prefix from qualified name
              #
              # @param qualified_name [String] The qualified name (e.g., "gml:CodeType")
              # @return [String] The prefix (e.g., "gml")
              def extract_prefix(qualified_name)
                qualified_name.to_s.split(":").first
              end
            end
          end
        end
      end
    end
  end
end
