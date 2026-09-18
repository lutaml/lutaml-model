# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Handles attribute definition methods for Serialize::ClassMethods
      #
      # Extracted from serialize.rb to improve code organization.
      # Provides methods for defining and validating model attributes.
      module AttributeDefinition
        # Define attribute methods on the model class
        #
        # @param attr [Attribute] The attribute to define methods for
        # @param register [Symbol, nil] The register for type resolution
        # Compile (per class, cached) the method that seeds every attribute
        # with its "no data arrived" sentinel: collections share the frozen
        # LAZY_EMPTY_COLLECTION, scalars share the UninitializedClass
        # singleton. Compiled once instead of walked per instance — the
        # grammars-compile-don't-interpret rule applied to object state.
        # Compile (per class and register, on demand) the method that
        # seeds every attribute with its "no data arrived" sentinel:
        # collections share the frozen LAZY_EMPTY_COLLECTION, scalars
        # share the UninitializedClass singleton. Compiled once instead
        # of walked per instance — grammars compile, they don't
        # interpret.
        def compiled_state_defaults_name!(register_id)
          @state_defaults_names ||= {}
          name = @state_defaults_names[register_id]
          return name if name

          method_name = :"__init_state_defaults_#{register_id}"
          compile_state_defaults!(method_name, register_id)
          @state_defaults_names[register_id] = method_name
          method_name
        end

        def compile_state_defaults!(method_name, register_id = nil)
          attrs = attributes(register_id)

          if attrs.empty?
            define_method(method_name) do
              # no attributes to seed
            end
            return
          end

          lines = attrs.map do |name, attr|
            if attr.collection?
              "@#{name} = Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION"
            else
              "@#{name} = Lutaml::Model::UninitializedClass.instance"
            end
          end.join("\n")

          # class_eval interpolates per-attribute `@name = <sentinel>` lines:
          #   def __init_state_defaults_default
          #     @id = Lutaml::Model::UninitializedClass.instance
          #     @items = Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION
          #   end
          class_eval(<<~RUBY, __FILE__, __LINE__ + 1) # rubocop:disable Style/DocumentDynamicEvalDefinition
            def #{method_name}
            #{lines}
            end
          RUBY
        end

        # Historical getter shape for punctuation-named attributes and
        # any name the compiled form cannot express.
        def define_reflective_attribute_methods(name, attr)
          if attr.collection?
            define_method(name) do |*args|
              if args.empty?
                materialize_lazy_collection(name)
              else
                # Builder-style: g.member(item) appends to collection
                value = args.first
                current = instance_variable_get(:"@#{name}") || []
                new_value = current.is_a?(Array) ? current + [value] : value
                instance_variable_set(:"@#{name}", new_value)
                record_mutation(name, value)
                value
              end
            end
          else
            define_method(name) do |*args|
              if args.empty?
                instance_variable_get(:"@#{name}")
              else
                public_send(:"#{name}=", args.first)
                args.first
              end
            end
          end
        end

        def invalidate_state_defaults!
          # Opal's method_defined? takes no inherit flag (see the
          # setter_defined check in define_regular_attribute_methods).
          (@state_defaults_names ||= {}).each_key do |compiled|
            defined_now = if Lutaml::Model.opal?
                            method_defined?(compiled)
                          else
                            method_defined?(compiled, false)
                          end
            remove_method(compiled) if defined_now
          end
        end

        def define_attribute_methods(attr, register = nil)
          name = attr.name
          register_id = extract_register_id(register)

          if attr.enum?
            add_enum_methods_to_model(
              model,
              name,
              attr.options[:values],
              collection: attr.options[:collection],
            )
          elsif attr.derived? && name != attr.method_name
            unless method_defined?(name, false)
              define_method(name) do
                value = public_send(attr.method_name)
                # Cast the derived value to the specified type. cast_derived,
                # not cast_element: this reader is its own casting entry point,
                # so it needs the same "nothing arrived, nothing to cast" rule
                # the writers get, and a collection has to come back as one.
                attr.cast_derived(value, register_id)
              end
            end
          elsif attr.unresolved_type == Lutaml::Model::Type::Reference
            define_reference_methods(name, register_id)
          else
            define_regular_attribute_methods(name, attr)
          end
        end

        # Define reference-type attribute methods
        #
        # Reference types store a reference key that can be resolved to
        # the actual object.
        #
        # @param name [Symbol] The attribute name
        # @param register [Symbol] The register ID
        def define_reference_methods(name, register)
          register_id = register
          attr = attributes[name]

          unless method_defined?(:"#{name}_ref", false)
            define_method("#{name}_ref") do
              instance_variable_get(:"@#{name}_ref")
            end
          end

          key_method_name = if attr.options[:collection]
                              Utils.pluralize(attr.options[:ref_key_attribute].to_s)
                            else
                              attr.options[:ref_key_attribute]
                            end

          unless method_defined?(:"#{name}_#{key_method_name}", false)
            define_method("#{name}_#{key_method_name}") do
              ref = instance_variable_get(:"@#{name}_ref")
              # attr.reference_key first: once a collection reader has stored
              # its resolved objects, the key has to come back off the object.
              resolve_reference_key(attr.reference_key(ref))
            end
          end

          unless method_defined?(name, false)
            if attr.options[:collection]
              define_method(name) do
                materialize_reference_collection(name)
              end
            else
              define_method(name) do
                ref = instance_variable_get(:"@#{name}_ref")
                resolve_reference_value(ref)
              end
            end
          end

          unless method_defined?(:"#{name}=", false)
            define_method(:"#{name}=") do |value|
              value_set_for(name)
              casted_value = value
              unless casted_value.is_a?(Lutaml::Model::Type::Reference)
                casted_value = attr.cast_value(value, register_id)
              end

              instance_variable_set(:"@#{name}_ref", casted_value)

              resolved_reference = resolve_reference_key(casted_value)
              instance_variable_set(:"@#{name}", resolved_reference)
            end
          end
        end

        # Define regular (non-reference, non-enum) attribute methods
        #
        # @param name [Symbol] The attribute name
        # @param attr [Attribute] The attribute definition
        # Plain identifier names compile to `@name` reads; punctuation
        # names (`mixed?`) keep the reflective path (@name is not valid
        # Ruby for them).
        PLAIN_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

        def define_regular_attribute_methods(name, attr)
          unless name.to_s.match?(PLAIN_NAME)
            return define_reflective_attribute_methods(name, attr)
          end

          # Getters compile with a sentinel default argument instead of a
          # `*args` splat: the splat allocated an (almost always empty)
          # Array on EVERY read — the largest per-call allocation source
          # on instance-heavy parses (TODO.max-perf/06). The optional-arg
          # form allocates nothing, and the read is a direct @ivar.
          if attr.collection?
            # class_eval interpolates, e.g.:
            #   def items(arg = Lutaml::Model::Serialize::NO_ARG)
            #     if arg.equal?(Lutaml::Model::Serialize::NO_ARG)
            #       materialize_lazy_collection(:items)
            #     else
            #       ... builder append ...
            #     end
            #   end
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1) # rubocop:disable Style/DocumentDynamicEvalDefinition
              def #{name}(arg = Lutaml::Model::Serialize::NO_ARG)
                if arg.equal?(Lutaml::Model::Serialize::NO_ARG)
                  materialize_lazy_collection(:#{name})
                else
                  current = @#{name} || []
                  new_value = current.is_a?(Array) ? current + [arg] : arg
                  @#{name} = new_value
                  record_mutation(:#{name}, arg)
                  arg
                end
              end
            RUBY
          else
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1) # rubocop:disable Style/DocumentDynamicEvalDefinition
              def #{name}(arg = Lutaml::Model::Serialize::NO_ARG)
                if arg.equal?(Lutaml::Model::Serialize::NO_ARG)
                  @#{name}
                else
                  public_send(:"#{name}=", arg)
                  arg
                end
              end
            RUBY
          end

          enum_shorthand_names = instance_variable_get(:@__enum_shorthand_names__) || Set.new
          # Opal's Module#method_defined? only accepts 1 arg (MRI accepts
          # the optional `inherit` flag). Skip the flag there — the
          # difference only matters for inherited-method filtering.
          setter_defined = if Lutaml::Model.opal?
                             method_defined?(:"#{name}=")
                           else
                             method_defined?(:"#{name}=", false)
                           end
          return if setter_defined && !enum_shorthand_names.include?(name.to_s)

          # class_eval'd bodies cannot close over locals; a hidden
          # define_method accessor holds the Attribute handle.
          attr_reader_method = :"__attribute_definition_#{name}"
          unless method_defined?(attr_reader_method, false)
            define_method(attr_reader_method) { attr }
          end

          if attr.collection?
            # class_eval interpolates, e.g.:
            #   def items=(value)
            #     value_set_for(:items)
            #     value = ATTR.cast_value(value, lutaml_register)
            #     current = @items
            #     ... sentinel preservation ...
            #     record_mutation_collection(:items, value)
            #   end
            # The compiled body writes @items directly: the define_method
            # form interpolated "@items" name strings per call — one per
            # setter invocation on instance-heavy parses (TODO.max-perf/06).
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1) # rubocop:disable Style/DocumentDynamicEvalDefinition
              def #{name}=(value)
                value_set_for(:#{name})
                value = __attribute_definition_#{name}.cast_value(value, lutaml_register)
                current = @#{name}
                if current.equal?(Lutaml::Model::Serialize::LAZY_EMPTY_COLLECTION) &&
                    (value.nil? || Lutaml::Model::Utils.uninitialized?(value))
                  # Sentinel stays — no allocation for truly empty collections
                else
                  @#{name} = value
                end
                record_mutation_collection(:#{name}, value)
              end
            RUBY
          else
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1) # rubocop:disable Style/DocumentDynamicEvalDefinition
              def #{name}=(value)
                value_set_for(:#{name})
                value = __attribute_definition_#{name}.cast_value(value, lutaml_register)
                @#{name} = value
                record_mutation(:#{name}, value)
              end
            RUBY
          end
        end

        # Define an attribute for the model
        #
        # @param name [Symbol] The attribute name
        # @param type [Class, Symbol, Hash] The attribute type
        # @param options [Hash] Attribute options
        # @return [Attribute] The created attribute
        def attribute(name, type, options = {})
          type, options = process_type_hash(type, options) if type.is_a?(::Hash)

          if type.is_a?(::Array)
            options = options.merge(union_member_types: type)
            type = Lutaml::Model::Type::Union
          end

          # Handle direct method option in options hash
          if options[:method]
            options[:method_name] = options.delete(:method)
          end

          attr = Attribute.new(name, type, options)
          @attributes[name] = attr
          @merged_attributes_cache = nil
          invalidate_state_defaults!
          define_attribute_methods(attr)

          attr
        end

        # Restrict options on an existing attribute
        #
        # @param name [Symbol] The attribute name to restrict
        # @param options [Hash] New options to merge
        # @return [Symbol] The attribute name
        def restrict(name, options = {})
          register_id = options.delete(:register) || Lutaml::Model::Config.default_register

          if !@attributes.key?(name) && !register_record(register_id)&.dig(
            :attributes, name
          )
            return restrict_attributes[name] = options if any_importable_models?

            raise Lutaml::Model::UndefinedAttributeError.new(name, self)
          end

          validate_attribute_options!(name, options)
          attr = attributes(register_id)[name]
          attr.options.merge!(options)
          attr.process_options!
          name
        end

        # Check if there are any importable models
        #
        # @return [Boolean] True if there are pending imports
        def any_importable_models?
          importable_choices.any? || importable_models.any?
        end

        # Validate attribute options
        #
        # @param name [Symbol] The attribute name
        # @param options [Hash] The options to validate
        # @raise [InvalidAttributeOptionsError] If invalid options are present
        def validate_attribute_options!(name, options)
          invalid_opts = options.keys - Attribute::ALLOWED_OPTIONS
          return if invalid_opts.empty?

          raise Lutaml::Model::InvalidAttributeOptionsError.new(name,
                                                                invalid_opts)
        end
      end
    end
  end
end
