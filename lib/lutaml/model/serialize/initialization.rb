# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles initialization and namespace methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for class initialization and namespace handling.
      module Initialization
        # Class-level namespace getter/setter.
        #
        # No-op by default. When XML format is loaded, this is overridden
        # via prepend to provide XML namespace handling.
        #
        # @param _ns_class [Class, nil] Namespace class (handled by format modules)
        # @return [Class, nil] the namespace class
        def namespace(_ns_class = nil)
          @namespace_class
        end

        # Get the namespace URI for this Model
        #
        # @return [String, nil] the namespace URI
        def namespace_uri
          nil
        end

        # Get the default namespace prefix for this Model
        #
        # @return [String, nil] the namespace prefix
        def namespace_prefix
          nil
        end

        # Set the register context for this Model class.
        #
        # This is called by Register#register_model to ensure the class
        # knows its register context for proper instance initialization.
        #
        # @param register_id [Symbol] The register ID
        # @return [void]
        def set_register_context(register_id)
          return if instance_variable_defined?(:@register)

          @register = register_id
        end

        # Get or set the default register for this Model class.
        #
        # Override in subclasses to specify a preferred default register context.
        # This allows versioned schemas (e.g., MML v2, v3) to use their own
        # register by default when instances are created without explicit register.
        #
        # @return [Symbol, nil] The default register ID or nil to use Config.default_register
        #
        # @example
        #   module Mml
        #     class V2Base < Lutaml::Model::Serializable
        #       def self.lutaml_default_register
        #         :mml_v2
        #       end
        #     end
        #   end
        #
        #   class Mml::V2::Math < V2Base
        #     # Mml::V2::Math.new uses :mml_v2 by default
        #   end
        def lutaml_default_register
          nil
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
          @mappings = Utils.deep_dup(source_class.mappings) || {}
          @attributes = Utils.deep_dup(source_class.class_attributes) || {}
          @choice_attributes = deep_duplicate_choice_attributes(source_class)
          @register_records = Utils.deep_dup(
            source_class.register_records,
          ) || ::Hash.new do |hash, key|
                 hash[key] = { attributes: {}, choice_attributes: [] }
               end
          model(self)
        end

        # Deep duplicate choice attributes from a source class
        #
        # @param source_class [Class] The source class
        # @return [Array] The duplicated choice attributes
        def deep_duplicate_choice_attributes(source_class, register = nil)
          choice_attrs = Array(source_class.choice_attributes)
          choice_attrs.map do |choice_attr|
            choice_attr.deep_duplicate(self, register)
          end
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

        # Raw class-level attributes without register merging.
        # Used by initialize_attrs during class inheritance.
        # @return [Hash] The raw attributes hash
        def class_attributes
          @attributes
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
          # Hook for format-specific mapping import resolution.
          # XML overrides this to call mappings[:xml]&.ensure_mappings_imported!(register)
          ensure_format_mapping_imports!(register)
        end

        # Hook for format-specific mapping import resolution.
        # Override in format modules (e.g., XML prepends to resolve XML mapping imports).
        #
        # @param _register [Symbol, nil] The register context
        def ensure_format_mapping_imports!(_register = nil)
          # No-op by default; XML overrides via prepend
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

          # Clear Transform cache (uses class identity as key)
          Transform.invalidate_for(self, register_id)

          # Clear import resolution guard flags so imports can be re-resolved
          instance_variables.each do |ivar|
            ivar_s = ivar.to_s
            remove_instance_variable(ivar) if ivar_s.start_with?("@_imports_resolved_") ||
              ivar_s == "@_register_methods_defined"
          end
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
                                          :values_set_for) do |attribute_names|
            @using_default ||= {}
            attribute_names.each { |name| @using_default[name] = false }
          end

          Utils.add_method_if_not_defined(klass,
                                          :using_default?) do |attribute_name|
            @using_default ||= {}
            !!@using_default[attribute_name]
          end

          # Hook for format-specific model methods (e.g., XML adds ordered, mixed, element_order)
          add_format_specific_model_methods(klass)
        end

        # Hook for format-specific model methods.
        # XML overrides via FormatConversion prepend to add XML accessors.
        #
        # @param _klass [Class] The model class
        def add_format_specific_model_methods(_klass)
          # No-op by default
        end

        # Cast a value (pass-through implementation)
        #
        # @param value [Object] The value to cast
        # @return [Object] The same value
        def cast(value)
          value
        end

        # Whether instances of this class should be registered in the
        # global Store for reference resolution. Defaults to true for
        # backward compatibility. Use `skip_reference_registration` to
        # opt out for classes that never participate in cross-referencing.
        def reference_resolvable?
          return true unless instance_variable_defined?(:@skip_reference_registration)

          !@skip_reference_registration
        end

        # Opt out of Store registration for this class.
        # Instances will not be tracked in the global Store, saving
        # memory and registration overhead for classes that are never
        # resolved by reference (no xml_id or similar attributes).
        def skip_reference_registration
          @skip_reference_registration = true
        end

        # Define a choice constraint
        #
        # @param min [Integer] Minimum number of choices
        # @param max [Integer] Maximum number of choices
        # @param block [Proc] The choice definition block
        def choice(min: 1, max: 1, format: nil, &block)
          @choice_attributes << Choice.new(self, min, max,
                                           format: format).tap do |c|
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

        # Allocate an instance for deserialization without calling initialize.
        #
        # Skips the expensive initialize_attributes pass (which iterates all
        # attributes to set defaults). The XML mapping pipeline sets values
        # directly via rule.deserialize instead. Uses Hash.new(true) as the
        # default for @using_default so that using_default? returns true for
        # all attributes until value_set_for is called.
        #
        # @param register [Symbol, nil] The register context
        # @return [Object] The allocated instance
        def allocate_for_deserialization(register = nil)
          instance = allocate
          register_id = extract_register_id(register)
          instance.finalize_deserialization(register_id)
          instance
        end

        # Define register-specific attribute methods on the class itself.
        #
        # Called once per (class, register) combination. Replaces per-instance
        # singleton class allocation with class-level method definitions,
        # preserving Ruby's inline method cache optimization.
        #
        # @param register_id [Symbol] The register ID
        def ensure_register_methods_defined(register_id)
          return if register_id == :default

          @_register_methods_defined ||= {}
          return if @_register_methods_defined[register_id]

          reg_record = register_records[register_id]
          return unless reg_record

          default_attrs = class_attributes || {}
          reg_record_attrs = reg_record[:attributes] || {}

          reg_record_attrs.each do |name, attr|
            next if default_attrs.key?(name)
            next if method_defined?(name, false)

            if attr.collection?
              define_collection_register_methods(name)
            else
              define_scalar_register_methods(name)
            end
          end

          @_register_methods_defined[register_id] = true
        end

        private

        # Define getter/setter for a scalar register-specific attribute.
        def define_scalar_register_methods(name)
          define_method(name) do |*args|
            if args.empty?
              instance_variable_get(:"@#{name}")
            else
              public_send(:"#{name}=", args.first)
              track_order(name, args.first, nil) if @__order_tracking__
              args.first
            end
          end

          define_method(:"#{name}=") do |value|
            value_set_for(name)
            reg_attr = resolve_register_attr(name)
            value = reg_attr.cast_value(value, lutaml_register)
            instance_variable_set(:"@#{name}", value)
          end
        end

        # Define getter/setter for a collection register-specific attribute.
        def define_collection_register_methods(name)
          define_method(name) do |*args|
            if args.empty?
              current = instance_variable_get(:"@#{name}")
              current.equal?(LAZY_EMPTY_COLLECTION) ? [] : current
            else
              value = args.first
              current = instance_variable_get(:"@#{name}")
              current = [] if current.equal?(LAZY_EMPTY_COLLECTION)
              new_value = current.is_a?(Array) ? current + [value] : value
              instance_variable_set(:"@#{name}", new_value)
              track_order(name, value, nil) if @__order_tracking__
              value
            end
          end

          define_method(:"#{name}=") do |value|
            value_set_for(name)
            reg_attr = resolve_register_attr(name)
            value = reg_attr.cast_value(value, lutaml_register)
            current = instance_variable_get(:"@#{name}")
            if current.equal?(LAZY_EMPTY_COLLECTION) &&
                (value.nil? || Lutaml::Model::Utils.uninitialized?(value))
              # Sentinel stays — no allocation for empty collections
            else
              instance_variable_set(:"@#{name}", value)
            end
          end
        end

        # Extract and normalize register ID with default fallback
        #
        # Resolution order:
        # 1. Explicit register parameter
        # 2. Class's lutaml_default_register (for versioned schemas)
        # 3. Global Config.default_register
        #
        # @param register [Symbol, String, nil] The register identifier
        # @return [Symbol] The normalized register ID
        def extract_register_id(register)
          register&.to_sym || lutaml_default_register || Lutaml::Model::Config.default_register
        end
      end
    end
  end
end
