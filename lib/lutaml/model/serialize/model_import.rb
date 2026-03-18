# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles model import/export methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for importing attributes and mappings from other models.
      module ModelImport
        # Check if register has a root mapping
        #
        # @param register [Symbol, nil] The register to check
        # @return [Boolean] True if the model has a root mapping
        def root?(register)
          mappings_for(:xml, register)&.root?
        end

        # Raise error if importing a model with a root element
        #
        # @param model [Class] The model to check
        # @param register [Symbol, nil] The register context
        # @raise [ImportModelWithRootError] If model has a root mapping
        def import_model_with_root_error(model, register = nil)
          return unless model.mappings.key?(:xml) && model.root?(register)

          raise Lutaml::Model::ImportModelWithRootError.new(model)
        end

        # Import attributes from another model
        #
        # @param model [Class, Symbol, String] The model to import from
        # @param register_id [Symbol, nil] The register context
        def import_model_attributes(model, register_id = nil)
          if model.is_a?(Symbol) || model.is_a?(String)
            importable_models[:import_model_attributes] << model.to_sym
            @models_imported = false
            @choices_imported = false
            setup_trace_point
            return
          end

          model.attributes(register_id).each_value do |attr|
            define_attribute_methods(attr, register_id)
          end

          @attributes.merge!(Utils.deep_dup(model.attributes))
          @choice_attributes.concat(deep_duplicate_choice_attributes(model))
        end

        # Import mappings from another model
        #
        # @param model [Class] The model to import from
        # @param register_id [Symbol, nil] The register context
        def import_model_mappings(model, register_id = nil)
          Lutaml::Model::Config::AVAILABLE_FORMATS.each do |format|
            next unless model.mappings.key?(format)

            klass = ::Lutaml::Model::Config.mappings_class_for(format)
            @mappings[format] ||= klass.new
            @mappings[format].import_model_mappings(model, register_id)
          end
        end

        # Import both attributes and mappings from another model
        #
        # @param model [Class, Symbol, String] The model to import from
        # @param register_id [Symbol, nil] The register context
        def import_model(model, register_id = nil)
          if model.is_a?(Symbol) || model.is_a?(String)
            importable_models[:import_model] << model.to_sym
            @models_imported = false
            @choices_imported = false
            setup_trace_point
            return
          end

          import_model_attributes(model, register_id)
          import_model_mappings(model, register_id)
        end

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

        # Ensure all model imports are resolved
        #
        # @param register_id [Symbol, nil] The register context
        def ensure_model_imports!(register_id = nil)
          return if @models_imported

          # CRITICAL: Prevent re-entrant calls during import resolution
          # Set flag BEFORE processing to prevent infinite recursion
          @models_imported = true

          register_id ||= Lutaml::Model::Config.default_register

          # Track if all imports were successfully resolved
          all_resolved = true

          importable_models.each do |method, models|
            models.uniq.each do |model|
              model_class = Lutaml::Model::GlobalContext.resolve_type(model,
                                                                      register_id)

              # Skip if model not registered yet - will retry later
              if model_class.nil?
                all_resolved = false
                next
              end

              # CRITICAL: Recursively finalize imported class BEFORE using it
              # This ensures ALL imports are resolved at definition time, not runtime
              if model_class.is_a?(Class) && model_class.include?(Lutaml::Model::Serialize)
                model_class.ensure_imports!(register_id)
              end

              import_model_with_root_error(model_class, register_id)
              @model.public_send(method, model_class, register_id)
            end
          end

          importable_models.clear

          # CRITICAL: Only mark as imported if ALL imports were successfully resolved
          # If any were skipped (not registered yet), allow retry later
          @models_imported = true if all_resolved
        end

        # Ensure all choice imports are resolved
        #
        # @param register_id [Symbol, nil] The register context
        def ensure_choice_imports!(register_id = nil)
          return if @choices_imported

          register_id ||= Lutaml::Model::Config.default_register

          # Track if all imports were successfully resolved
          all_resolved = true

          importable_choices.each do |choice, choice_imports|
            choice_imports.each do |method, models|
              until models.uniq.empty?
                model_class = Lutaml::Model::GlobalContext.resolve_type(
                  models.shift, register_id
                )

                # Skip if model not registered yet - will retry later
                if model_class.nil?
                  all_resolved = false
                  next
                end

                # CRITICAL: Recursively finalize imported class BEFORE using it
                if model_class.is_a?(Class) && model_class.include?(Lutaml::Model::Serialize)
                  model_class.ensure_imports!(register_id)
                end

                choice.public_send(
                  method,
                  model_class,
                  register_id,
                )
              end
            end
          end

          # CRITICAL: Only mark as imported if ALL imports were successfully resolved
          # If any were skipped (not registered yet), allow retry later
          @choices_imported = true if all_resolved
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

        # Check for conflicting sort configurations
        #
        # @return [Boolean] True if there's a conflict
        def collection_with_conflicting_sort?
          self <= Lutaml::Model::Collection &&
            @mappings[:xml].ordered? &&
            !!@sort_by_field
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

            # Ensure model-level imports (attributes, choices)
            type_class.ensure_imports!(register)

            # CRITICAL: Also ensure mapping-level imports (XML element/attribute mappings)
            # Child models may have symbol-based import_model_mappings that need resolution
            type_class.mappings[:xml]&.ensure_mappings_imported!(register)

            # Recursively process child's children, passing THE SAME visited set
            type_class.ensure_child_imports_resolved!(register, visited)
          end
        end
      end
    end
  end
end
