# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Registry for XmlNamespace classes to ensure identity and prevent
      # configuration loss during planning phase.
      #
      # Problem: Anonymous XmlNamespace classes were being recreated multiple
      # times, losing their configuration (e.g., element_form_default changes
      # from :qualified to :unqualified).
      #
      # Solution: Single registry ensures ONE Class object per unique
      # configuration, preserving namespace semantics throughout serialization.
      class NamespaceClassRegistry
        # Get singleton instance
        def self.instance
          @instance ||= new
        end

        def initialize
          @classes = {}
          @named_classes = {}
          @mutex = Mutex.new
        end

        # Get or create anonymous namespace class with specific configuration.
        # Returns same Class object for identical configurations.
        #
        # @param uri [String, nil] Namespace URI
        # @param prefix [String, nil] Default prefix
        # @param element_form_default [Symbol] :qualified or :unqualified
        # @param attribute_form_default [Symbol] :qualified or :unqualified
        # @return [Class] XmlNamespace subclass
        def get_or_create(uri: nil, prefix: nil,
                         element_form_default: :qualified,
                         attribute_form_default: :unqualified)
          key = build_key(uri, prefix, element_form_default,
                         attribute_form_default)

          @mutex.synchronize do
            # First check if a named class with this exact configuration exists
            # This ensures backward compatibility: string and class syntax produce same result
            return @named_classes[key] if @named_classes.key?(key)

            # Otherwise get or create anonymous class
            @classes[key] ||= create_anonymous_class(
              uri, prefix, element_form_default, attribute_form_default
            )
          end
        end

        # Register a named (user-defined) namespace class.
        # Ensures the class is properly configured and prevents duplicates.
        #
        # @param ns_class [Class] XmlNamespace subclass
        # @return [Class] The registered class
        # @raise [ArgumentError] if class is invalid
        def register_named(ns_class)
          validate_namespace_class!(ns_class)

          key = build_key_from_class(ns_class)

          @mutex.synchronize do
            @named_classes[key] ||= ns_class
          end
        end

        # Clear registry (for testing only)
        # @api private
        def clear!
          @mutex.synchronize do
            @classes.clear
            @named_classes.clear
          end
        end

        private

        # Build unique key for namespace configuration
        def build_key(uri, prefix, element_form, attribute_form)
          [
            uri || "nil",
            prefix || "nil",
            element_form.to_s,
            attribute_form.to_s,
          ].join("|")
        end

        # Build key from existing namespace class
        def build_key_from_class(ns_class)
          build_key(
            ns_class.uri,
            ns_class.prefix_default,
            ns_class.element_form_default,
            ns_class.attribute_form_default
          )
        end

        # Create anonymous XmlNamespace subclass with configuration
        def create_anonymous_class(uri, prefix, element_form, attribute_form)
          Class.new(Lutaml::Model::Xml::Namespace) do
            self.uri uri if uri
            self.prefix_default prefix if prefix
            self.element_form_default element_form
            self.attribute_form_default attribute_form
          end
        end

        # Validate namespace class is proper subclass
        def validate_namespace_class!(ns_class)
          unless ns_class.is_a?(Class) &&
                 ns_class < Lutaml::Model::Xml::Namespace
            raise ArgumentError,
                  "Expected XmlNamespace subclass, got #{ns_class.class}"
          end
        end
      end
    end
  end
end