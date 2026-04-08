# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles model import/export methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for importing attributes and mappings from other models.
      module ModelImport
        # Check if register has a root mapping (XML-specific)
        #
        # Returns false by default. When Lutaml::Xml is loaded,
        # this is overridden to check XML mappings via prepend.
        #
        # @param register [Symbol, nil] The register to check
        # @return [Boolean] True if the model has a root mapping
        def root?(_register = nil)
          false
        end

        # Raise error if importing a model with a root element
        #
        # @param model [Class] The model to check
        # @param register [Symbol, nil] The register context
        # @raise [ImportModelWithRootError] If model has a root mapping
        def import_model_with_root_error(model, register = nil)
          return unless model.root?(register)

          raise Lutaml::Model::ImportModelWithRootError.new(model)
        end

        # Import attributes from another model
        #
        # Deferred path (model is a Symbol/String): stores model reference per-register
        # and resolves lazily on first access via ensure_imports!.
        #
        # Immediate path (model is a Class): merges into class-level @attributes
        # for default register, or register-specific storage for non-default registers.
        #
        # @param model [Class, Symbol, String] The model to import from
        # @param register_id [Symbol, nil] The register context
        def import_model_attributes(model, register_id = nil)
          if model.is_a?(Symbol) || model.is_a?(String)
            reg = extract_register_id(register_id)
            importable_models[:import_model_attributes] << model.to_sym
            @models_imported = (@models_imported || {}).merge(reg => false)
            @choices_imported = (@choices_imported || {}).merge(reg => false)
            setup_trace_point
            return
          end

          reg = extract_register_id(register_id)
          if reg != :default
            register_only_import_model_attributes(model, register_id)
            return
          end

          # Default register: merge into class-level storage
          model.attributes.each_value { |attr| define_attribute_methods(attr) }
          @attributes.merge!(Utils.deep_dup(model.attributes))
          @choice_attributes.concat(deep_duplicate_choice_attributes(model))
          # Ensure @models_imported is a hash; migrate from legacy nil/false state
          @models_imported ||= {}
          @models_imported[reg] = true
        end

        # Import mappings from another model
        #
        # Delegates to format-specific import_model_mappings which stores in
        # register-specific storage when register_id is non-default.
        #
        # @param model [Class] The model to import from
        # @param register_id [Symbol, nil] The register context
        def import_model_mappings(model, register_id = nil)
          Lutaml::Model::FormatRegistry.formats.each do |format|
            next unless model.mappings.key?(format)

            klass = ::Lutaml::Model::Config.mappings_class_for(format)
            @mappings[format] ||= klass.new
            mapping = @mappings[format]
            if mapping.respond_to?(:import_model_mappings)
              mapping.import_model_mappings(model,
                                            register_id)
            end
          end
        end

        # Import both attributes and mappings from another model
        #
        # @param model [Class, Symbol, String] The model to import from
        # @param register_id [Symbol, nil] The register context
        def import_model(model, register_id = nil)
          if model.is_a?(Symbol) || model.is_a?(String)
            reg = extract_register_id(register_id)
            importable_models[:import_model] << model.to_sym
            @models_imported = (@models_imported || {}).merge(reg => false)
            @choices_imported = (@choices_imported || {}).merge(reg => false)
            setup_trace_point
            return
          end

          import_model_attributes(model, register_id)
          import_model_mappings(model, register_id)
        end

        # Import attributes from another model into register-specific storage only.
        # Used for non-default registers where attributes should NOT be merged
        # into the class-level @attributes.
        #
        # @param model [Class] The model to import from
        # @param register_id [Symbol] The register context (must be non-default)
        def register_only_import_model_attributes(model, register_id)
          model.attributes(register_id).each_value do |attr|
            define_attribute_methods(attr, register_id)
          end

          @register_records[register_id] ||= { attributes: {},
                                               choice_attributes: [] }
          @register_records[register_id][:attributes].merge!(Utils.deep_dup(model.attributes(register_id)))
          @register_records[register_id][:choice_attributes].concat(
            deep_duplicate_choice_attributes(model, register_id),
          )
        end
        private :register_only_import_model_attributes

        # Get hash of importable models (deferred imports)
        #
        # @return [MappingHash] Hash of method names to model arrays
        def importable_models
          @importable_models ||= MappingHash.new { |h, k| h[k] = [] }
        end

        # Get hash of restrict attributes (deferred restrictions)
        #
        # @return [MappingHash] Hash of attribute names to options
        def restrict_attributes
          @restrict_attributes ||= MappingHash.new
        end

        # Get hash of importable choices (deferred choice imports)
        #
        # @return [MappingHash] Nested hash of choices to imports
        def importable_choices
          @importable_choices ||= MappingHash.new do |h, k|
            h[k] = MappingHash.new do |h1, k1|
              h1[k1] = []
            end
          end
        end

        # Ensure all model imports are resolved for a specific register
        #
        # @param register_id [Symbol, nil] The register context
        def ensure_model_imports!(register_id = nil)
          register_id ||= Lutaml::Model::Config.default_register
          @models_imported = {} if @models_imported.nil? || @models_imported == false
          return if @models_imported[register_id] || Utils.present?(@register_records[register_id][:attributes])

          @models_imported[register_id] = true
          all_resolved = true

          importable_models.each do |method, models|
            models.uniq.each do |model|
              model_class = begin
                Lutaml::Model::GlobalContext.resolve_type(model, register_id)
              rescue Lutaml::Model::UnknownTypeError
                nil
              end

              if model_class.nil?
                all_resolved = false
                next
              end

              if model_class.is_a?(Class) && model_class.include?(Lutaml::Model::Serialize)
                model_class.ensure_imports!(register_id)
              end

              import_model_with_root_error(model_class, register_id)
              @model.public_send(method, model_class, register_id)
            end
          end

          @models_imported[register_id] = all_resolved
        end

        # Ensure all choice imports are resolved for a specific register
        #
        # @param register_id [Symbol, nil] The register context
        def ensure_choice_imports!(register_id = nil)
          register_id ||= Lutaml::Model::Config.default_register
          @choices_imported = {} if @choices_imported.nil? || @choices_imported == false
          return if @choices_imported[register_id] || Utils.present?(@register_records[register_id][:choice_attributes])

          @choices_imported[register_id] = true
          all_resolved = true

          importable_choices.each do |choice, choice_imports|
            choice_imports.each do |method, models|
              models.uniq.each do |model|
                model_class = begin
                  Lutaml::Model::GlobalContext.resolve_type(model, register_id)
                rescue Lutaml::Model::UnknownTypeError
                  nil
                end

                if model_class.nil?
                  all_resolved = false
                  next
                end

                if model_class.is_a?(Class) && model_class.include?(Lutaml::Model::Serialize)
                  model_class.ensure_imports!(register_id)
                end

                choice.public_send(method, model_class, register_id)
              end
            end
          end

          @choices_imported[register_id] = true if all_resolved
        end

        # Ensure all restrict attributes are applied
        #
        # @param register_id [Symbol, nil] The register context
        def ensure_restrict_attributes!(register_id = nil)
          return if restrict_attributes.empty?

          attrs = restrict_attributes.dup
          restrict_attributes.clear
          register_id ||= Lutaml::Model::Config.default_register
          attrs.each do |name, options_list|
            options_list[:register] = register_id
            restrict(name, options_list)
          end
        end

        # Setup trace point to detect class finalization
        #
        # Uses TracePoint to detect when a class definition is complete,
        # allowing deferred import resolution.
        def setup_trace_point
          @trace ||= TracePoint.new(:end) do |_tp|
            if include?(Lutaml::Model::Serialize)
              @finalized = true
              # NOTE: Do NOT resolve imports here - it's too early in the load process
              # Classes being imported may not be defined yet, causing circular errors
              # Imports will be resolved lazily on first use via ensure_imports!
              # BUT they will be resolved RECURSIVELY, preventing redundant resolution
              @trace.disable
            end
          end
          @trace.enable unless @trace.enabled?
        end

        # Check if the class has been finalized
        #
        # @return [Boolean] True if the class definition is complete
        def finalized?
          @finalized
        end

        # Check for conflicting sort configurations (XML-specific)
        #
        # Returns false by default. XML overrides to check @mappings[:xml].ordered?
        #
        # @return [Boolean] True if there's a conflict
        def collection_with_conflicting_sort?
          false
        end

        # Check and validate sort configurations
        #
        # @raise [SortingConfigurationConflictError] If there's a conflict
        def check_sort_configs!
          return unless collection_with_conflicting_sort?

          raise Lutaml::Model::SortingConfigurationConflictError.new
        end

        # Recursively ensure all child model imports are resolved
        #
        # Walks through all attributes and ensures any Serializable types
        # have BOTH model-level imports (attributes) AND mapping-level imports (XML) resolved
        # before serialization/deserialization begins.
        #
        # CRITICAL PERFORMANCE FIX (Session 122):
        # Uses a visited set to prevent redundant processing in large schemas.
        # Without this, OOXML-scale schemas (hundreds of classes) create exponential cascades.
        #
        # @param register [Symbol] the register ID
        # @param visited [Set<Class>, nil] classes already processed (internal use only)
        # @return [void]
        def ensure_child_imports_resolved!(register, visited = nil)
          return unless finalized?

          # Create visited set ONLY at top level (first call)
          # All recursive calls share the SAME set to prevent redundant processing
          visited ||= Set.new

          return if visited.include?(self) # Already processed this class

          visited.add(self) # Mark as visited BEFORE processing to prevent cycles

          # CRITICAL: Use direct instance variable access to avoid triggering ensure_imports!
          # Calling attributes(register) would trigger ensure_imports! which creates circular chains
          attrs = @attributes || {}
          attrs.each_value do |attr|
            type_class = attr.type(register)
            next unless type_class
            # Check if type_class is a Serializable class that needs import resolution
            next unless type_class.is_a?(Class) && type_class < Lutaml::Model::Serialize
            next if visited.include?(type_class) # Skip if already visited

            # Mark child as visited BEFORE processing to prevent cycles
            visited.add(type_class)

            # Ensure model-level imports (attributes, choices, and format-specific mappings)
            # ensure_imports! calls ensure_format_mapping_imports! which is overridden by XML
            type_class.ensure_imports!(register)

            # Recursively process child's children, passing THE SAME visited set
            type_class.ensure_child_imports_resolved!(register, visited)
          end
        end
      end
    end
  end
end
