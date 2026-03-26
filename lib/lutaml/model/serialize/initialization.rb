# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles initialization and namespace methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for class initialization and namespace handling.
      module Initialization
        # Class-level directive to set the namespace for this Model
        #
        # @deprecated Class-level namespace directive is deprecated for Serializable classes.
        #   Use namespace inside xml/json/yaml blocks instead:
        #     xml do
        #       namespace YourNamespace
        #     end
        #
        # @param ns_class [Class, nil] XmlNamespace class to associate with this model
        # @return [Class, nil] the XmlNamespace class
        #
        # @example INCORRECT: Class-level (deprecated, does nothing)
        #   class CustomModel < Lutaml::Model::Serializable
        #     namespace CustomNamespace  # Does nothing!
        #   end
        #
        # @example CORRECT: Inside xml block
        #   class CustomModel < Lutaml::Model::Serializable
        #     xml do
        #       namespace CustomNamespace  # Works correctly
        #     end
        #   end
        def namespace(ns_class = nil)
          if ns_class
            unless ns_class.is_a?(Class) && ns_class < Lutaml::Xml::Namespace
              raise ArgumentError,
                    "namespace must be an XmlNamespace class, got #{ns_class.class}"
            end

            # Warn about class-level namespace usage for Serializable classes
            warn_class_level_namespace_usage(ns_class)

            @namespace_class = ns_class
          end
          @namespace_class
        end

        # Get the namespace URI for this Model
        #
        # @return [String, nil] the namespace URI
        def namespace_uri
          @namespace_class&.uri
        end

        # Get the default namespace prefix for this Model
        #
        # @return [String, nil] the namespace prefix
        def namespace_prefix
          @namespace_class&.prefix_default
        end

        # Handle inheritance by copying parent's configuration
        #
        # @param subclass [Class] The inheriting class
        def inherited(subclass)
          super
          subclass.initialize_attrs(self)
        end

        # Handle inclusion by extending with ClassMethods
        #
        # @param base [Class] The including class
        def included(base)
          base.extend(ClassMethods)
          base.initialize_attrs(self)
        end

        # Initialize class attributes from a source class
        #
        # @param source_class [Class] The source class to copy from
        def initialize_attrs(source_class)
          @mappings = Utils.deep_dup(source_class.instance_variable_get(:@mappings)) || {}
          @attributes = Utils.deep_dup(source_class.instance_variable_get(:@attributes)) || {}
          @choice_attributes = deep_duplicate_choice_attributes(source_class)
          @register_records = Utils.deep_dup(
            source_class.instance_variable_get(:@register_records),
          ) || ::Hash.new { |hash, key| hash[key] = { attributes: {}, choice_attributes: [] } }
          instance_variable_set(:@model, self)
        end

        # Deep duplicate choice attributes from a source class
        #
        # @param source_class [Class] The source class
        # @return [Array] The duplicated choice attributes
        def deep_duplicate_choice_attributes(source_class, register = nil)
          choice_attrs = Array(source_class.instance_variable_get(:@choice_attributes))
          choice_attrs.map { |choice_attr| choice_attr.deep_duplicate(self, register) }
        end

        # Get all attributes for this model
        #
        # Merges class-level attributes with register-specific attributes.
        #
        # @param register [Symbol, nil] The register context
        # @return [Hash] The attributes hash
        def attributes(register = nil)
          ensure_imports!(register) if finalized?
          if @register_records&.any?
            @attributes.merge(@register_records[extract_register_id(register)][:attributes])
          else
            @attributes
          end
        end

        # Get all choice attributes for this model
        #
        # Merges class-level choice attributes with register-specific choice attributes.
        #
        # @param register [Symbol, nil] The register context
        # @return [Array] The choice attributes array
        def choice_attributes(register = nil)
          ensure_imports!(register) if finalized?
          if @register_records&.any?
            @choice_attributes + @register_records[extract_register_id(register)][:choice_attributes]
          else
            @choice_attributes
          end
        end

        # Ensure all imports are resolved
        #
        # @param register [Symbol, nil] The register context
        def ensure_imports!(register = nil)
          ensure_model_imports!(register)
          ensure_choice_imports!(register)
          ensure_restrict_attributes!(register)
          # REMOVED: XML mapping resolution here causes exponential cascade
          # Mappings will be resolved lazily in mappings_for when actually needed
          # CRITICAL: Ensure XML mapping imports are resolved (including sequence imports)
          # This handles deferred imports inside sequence blocks
          mappings[:xml]&.ensure_mappings_imported!(register)
        end

        # Clear all cached data for this model class
        #
        # Centralized caching (Phase 11.5):
        # - Type caches: GlobalContext.resolver
        # - Mapping caches: TransformationRegistry
        # - Transformation caches: TransformationRegistry
        #
        # @param register_id [Symbol, nil] If provided, only clear cache for this specific context
        def clear_cache(register_id = nil)
          # Clear centralized type cache in GlobalContext.resolver
          if defined?(Lutaml::Model::GlobalContext)
            GlobalContext.resolver.clear_cache(register_id)
          end

          # Clear centralized mapping and transformation caches
          # (Single Source of Truth - no longer uses instance variables)
          TransformationRegistry.instance.clear
        end

        # Get or set the model class
        #
        # @param klass [Class, nil] The model class to set
        # @return [Class] The model class
        def model(klass = nil)
          if klass
            @model = klass
            add_custom_handling_methods_to_model(klass)
          else
            @model
          end
        end

        # Add custom handling methods to a model class
        #
        # @param klass [Class] The model class
        def add_custom_handling_methods_to_model(klass)
          Utils.add_boolean_accessor_if_not_defined(klass, :ordered)
          Utils.add_boolean_accessor_if_not_defined(klass, :mixed)
          Utils.add_accessor_if_not_defined(klass, :element_order)
          Utils.add_accessor_if_not_defined(klass, :encoding)
          Utils.add_accessor_if_not_defined(klass, :doctype)

          Utils.add_method_if_not_defined(klass,
                                          :using_default_for) do |attribute_name|
            @using_default ||= {}
            @using_default[attribute_name] = true
          end

          Utils.add_method_if_not_defined(klass,
                                          :value_set_for) do |attribute_name|
            @using_default ||= {}
            @using_default[attribute_name] = false
          end

          Utils.add_method_if_not_defined(klass,
                                          :using_default?) do |attribute_name|
            @using_default ||= {}
            !!@using_default[attribute_name]
          end
        end

        # Cast a value (pass-through implementation)
        #
        # @param value [Object] The value to cast
        # @return [Object] The same value
        def cast(value)
          value
        end

        # Define a choice constraint
        #
        # @param min [Integer] Minimum number of choices
        # @param max [Integer] Maximum number of choices
        # @param block [Proc] The choice definition block
        def choice(min: 1, max: 1, &block)
          @choice_attributes << Choice.new(self, min, max).tap do |c|
            c.instance_eval(&block)
          end
        end

        # Get the register record for a specific register ID
        #
        # @param register_id [Symbol, nil] The register context
        # @return [Hash, nil] The register record hash or nil
        def register_record(register_id = nil)
          register_records[extract_register_id(register_id)]
        end

        # Convert register parameter to symbol
        #
        # @param name [Symbol, String, nil] The register name
        # @return [Symbol, nil] The register name as a symbol
        def register(name)
          name&.to_sym
        end

        private

        # Extract and normalize register ID with default fallback
        #
        # @param register [Symbol, String, nil] The register identifier
        # @return [Symbol] The normalized register ID
        def extract_register_id(register)
          register&.to_sym || Lutaml::Model::Config.default_register
        end

        # Issue deprecation warning for class-level namespace usage
        #
        # @param ns_class [Class] The namespace class
        def warn_class_level_namespace_usage(ns_class)
          return if @namespace_warning_issued

          warn <<~WARNING
            [Lutaml::Model] DEPRECATION WARNING: Class-level `namespace` directive is deprecated for Serializable classes.
            Class: #{name}
            Namespace: #{ns_class.name} (#{ns_class.uri})

            The class-level namespace directive does NOT apply namespace prefixes during serialization.

            INCORRECT (current usage):
              class #{name} < Lutaml::Model::Serializable
                namespace #{ns_class.name}  # Does nothing!
            #{'    '}
                xml do
                  element "element"
                  map_element "field", to: :field
                end
              end

            CORRECT (use namespace inside xml block):
              class #{name} < Lutaml::Model::Serializable
                xml do
                  element "element"
                  namespace #{ns_class.name}  # Works correctly!
                  map_element "field", to: :field
                end
              end

            This warning will become an error in the next major release.
          WARNING

          @namespace_warning_issued = true
        end
      end
    end
  end
end
