# frozen_string_literal: true

module Lutaml
  module KeyValue
    # KeyValue-specific transformation implementation.
    #
    # Transforms model instances into KeyValueElement trees without
    # serialization concerns. This provides the same architectural
    # pattern as Xml::Transformation but for key-value formats
    # (JSON, YAML, TOML).
    #
    # Architecture:
    # - Content Layer: KeyValueElement defines WHAT to serialize
    # - Presentation Layer: Adapters define HOW to serialize
    #
    # This is a critical step toward symmetric OOP architecture
    # across all serialization formats.
    class Transformation < Lutaml::Model::Transformation
      include Lutaml::Model::RenderPolicy

      private

      # Get the register ID, handling both Symbol and Register objects
      # This normalizes the register to an ID for backward compatibility
      #
      # @return [Symbol, nil] The register ID
      def register_id
        return @register if @register.is_a?(Symbol)

        @register_id
      end

      # Compile key-value mapping DSL into pre-compiled rules
      #
      # @param mapping_dsl [Mapping::KeyValueMapping] The mapping to compile
      # @return [Array<CompiledRule>] Array of compiled transformation rules
      def compile_rules(mapping_dsl)
        return [] unless mapping_dsl

        rules = []

        # Compile all mappings (key-value formats don't distinguish elements/attributes)
        mapping_dsl.mappings.each do |mapping_rule|
          rule = compile_mapping_rule(mapping_rule, mapping_dsl)
          rules << rule if rule
        end

        rules.compact
      end

      # Compile a mapping rule
      #
      # @param mapping_rule [Mapping::KeyValueMappingRule] The mapping rule
      # @param mapping_dsl [Mapping::KeyValueMapping] The mapping DSL (for accessing key_mappings)
      # @return [CompiledRule, nil] Compiled rule or nil
      def compile_mapping_rule(mapping_rule, mapping_dsl)
        # Access custom_methods and delegate early to check how to compile this rule
        custom_methods = mapping_rule.instance_variable_get(:@custom_methods)
        delegate = mapping_rule.instance_variable_get(:@delegate)

        attr_name = mapping_rule.to

        # For rules with custom methods but no 'to' attribute (e.g., with: { to: ... }),
        # we need to find the attribute name from the mapping
        if attr_name.nil? && !custom_methods.empty?
          # Try to infer attribute name from 'name' or 'from'
          # For multiple_mappings, name is an array - check each element
          attr_name = if mapping_rule.name
                        names = mapping_rule.name.is_a?(Array) ? mapping_rule.name : [mapping_rule.name]
                        names.map(&:to_sym).find do |n|
                          model_class.attributes(register_id)&.key?(n)
                        end
                      elsif mapping_rule.from.is_a?(String) && model_class.attributes(register_id)&.key?(mapping_rule.from.to_sym)
                        mapping_rule.from.to_sym
                      end
        end

        # For custom methods without an inferred attribute, use a placeholder
        # The custom method will handle all serialization logic
        if attr_name.nil? && !custom_methods.empty?
          # Use serialized name as placeholder for attribute name
          # The custom method handles everything, so we don't need a real attribute
          # For multiple_mappings, use the first name element
          first_name = if mapping_rule.name.is_a?(Array)
                         mapping_rule.name.first
                       else
                         mapping_rule.name
                       end
          attr_name = first_name&.to_sym || :__custom_method__

          # Create a dummy attribute type for custom methods
          attr_type = nil
          child_transformation = nil
          collection_info = nil
          value_transformer = nil
        else
          return nil unless attr_name

          # For delegated attributes, get attribute from delegated object's class
          if delegate
            # Get the delegate attribute from model to find the delegated class
            delegate_attr = model_class.attributes(register_id)&.[](delegate)
            return nil unless delegate_attr

            # Get the delegated class type
            delegated_class = delegate_attr.type(register_id)
            return nil unless delegated_class

            # Get the actual attribute from the delegated class
            attr = delegated_class.attributes&.[](attr_name)
          else
            # Get attribute definition from model class
            attr = model_class.attributes(register_id)&.[](attr_name)
          end
          return nil unless attr

          # Get attribute type
          attr_type = attr.type(register_id)

          # Build child transformation for nested models
          child_transformation = if attr_type.is_a?(Class) &&
              attr_type < Lutaml::Model::Serialize
                                   build_child_transformation(attr_type)
                                 end

          # Build collection info (include child_mappings for keyed collections)
          collection_info = if attr.collection?
                              info = { range: attr.options[:collection] }
                              # Add child_mappings if present (for map_key and map_value features)
                              # The keyed collection info might be stored in different places:
                              # 1. As child_mappings on the rule (from map_to_instance)
                              # 2. As @key_mappings on the mapping_dsl (separate __key_mapping entry)
                              # 3. As @value_mappings on the mapping_dsl (from map_value)
                              child_mappings_value = nil

                              # First try to get child_mappings from the rule
                              if mapping_rule.respond_to?(:child_mappings) && mapping_rule.child_mappings
                                child_mappings_value = mapping_rule.child_mappings
                              elsif mapping_rule.respond_to?(:hash_mappings) && mapping_rule.hash_mappings
                                child_mappings_value = mapping_rule.hash_mappings
                              end

                              # If not found on the rule, check the mapping_dsl for @key_mappings or @value_mappings
                              if child_mappings_value.nil? && mapping_dsl.respond_to?(:instance_variables)
                                # Check for @key_mappings (from map_key)
                                key_mappings = mapping_dsl.instance_variable_get(:@key_mappings)
                                if key_mappings
                                  # Extract the key attribute from the __key_mapping rule
                                  # The key_mappings has @to_instance which tells us which attribute is the key
                                  to_instance = key_mappings.instance_variable_get(:@to_instance) if key_mappings.respond_to?(:instance_variable_get)
                                  if to_instance
                                    # Create the child_mappings hash format: { id: :key }
                                    child_mappings_value = { to_instance.to_sym => :key }
                                  end
                                end

                                # Check for @value_mappings (from map_value)
                                if child_mappings_value.nil?
                                  value_mappings = mapping_dsl.instance_variable_get(:@value_mapping)
                                  if value_mappings && !value_mappings.empty?
                                    # value_mappings is already in the correct format: { attr_name => :value }
                                    child_mappings_value = value_mappings
                                  end
                                end
                              end

                              if child_mappings_value
                                info[:child_mappings] =
                                  child_mappings_value
                              end
                              info
                            end

          # Build value transformer (use delegate_attr for delegated attributes)
          value_transformer = build_value_transformer(mapping_rule,
                                                      delegate ? delegate_attr : attr)
        end

        # Access value_map directly
        value_map = mapping_rule.instance_variable_get(:@value_map)

        # Check if this is a raw mapping (map_all directive)
        is_raw_mapping = mapping_rule.respond_to?(:raw_mapping?) && mapping_rule.raw_mapping?

        # Get serialized name (key name in output)
        # For raw mappings, serialized_name is nil (content is merged directly)
        serialized_name = if is_raw_mapping
                            nil # Raw content has no key name
                          elsif !mapping_rule.name.nil?
                            # For multiple_mappings, use first element as serialized name
                            mapping_rule.name.is_a?(Array) ? mapping_rule.name.first.to_s : mapping_rule.name.to_s
                          elsif !mapping_rule.from.nil?
                            # For compatibility with multiple_mappings
                            mapping_rule.from.is_a?(Array) ? mapping_rule.from.first.to_s : mapping_rule.from.to_s
                          else
                            attr_name.to_s
                          end

        Lutaml::Model::CompiledRule.new(
          attribute_name: attr_name,
          serialized_name: serialized_name,
          attribute_type: attr_type,
          child_transformation: child_transformation,
          value_transformer: value_transformer,
          collection_info: collection_info,
          mapping_type: is_raw_mapping ? :raw : :key_value,
          render_nil: mapping_rule.render_nil,
          render_default: mapping_rule.render_default,
          render_empty: mapping_rule.render_empty,
          value_map: value_map,
          custom_methods: custom_methods,
          delegate: delegate,
          root_mappings: mapping_rule.root_mappings,
        )
      end

      # Build child transformation for nested model
      #
      # @param type_class [Class] The nested model class
      # @return [Transformation, nil] Child transformation or nil
      def build_child_transformation(type_class)
        return nil unless type_class.is_a?(Class) &&
          type_class.include?(Lutaml::Model::Serialize)

        # Get the mapping for the current format (not hardcoded to :json)
        mapping = type_class.mappings_for(format, register_id)

        # Create a new Transformation instance with the mapping
        self.class.new(type_class, mapping, format, register)
      end

      # Build value transformer from mapping rule and attribute
      #
      # @param mapping_rule [Mapping::KeyValueMappingRule] The mapping rule
      # @param attr [Attribute] The attribute definition
      # @return [Proc, Hash, nil] Value transformer
      def build_value_transformer(mapping_rule, attr)
        # Mapping-level transform takes precedence
        mapping_transform = mapping_rule.transform if mapping_rule.respond_to?(:transform)

        # Try to get attribute-level transform
        attr_transform = if attr.respond_to?(:transform)
                           attr.transform
                         elsif attr.options
                           attr.options[:transform]
                         end

        # Return mapping transform if present and non-empty
        if mapping_transform && !mapping_transform.empty?
          return mapping_transform
        end

        # Return attribute transform if present
        if attr_transform && !attr_transform.empty?
          return attr_transform
        end

        nil
      end

      # Check if a mapping rule should be applied based on only/except options
      #
      # @param rule [CompiledRule] The rule to check
      # @param options [Hash] Transformation options (may contain :only, :except)
      # @return [Boolean] true if the rule should be applied
      def valid_mapping?(rule, options)
        only = options[:only]
        except = options[:except]
        name = rule.attribute_name

        (except.nil? || !except.include?(name)) &&
          (only.nil? || only.include?(name))
      end

      public

      # Transform a model instance into KeyValueElement tree
      #
      # @param model_instance [Object] The model instance to transform
      # @param options [Hash] Transformation options (supports :only, :except for filtering)
      # @return [Lutaml::KeyValue::DataModel::Element] The root element
      def transform(model_instance, options = {})
        # For key-value formats, we typically don't have a named root
        # Instead, we create an anonymous root that holds all attributes
        root = Lutaml::KeyValue::DataModel::Element.new("__root__")

        # Apply each compiled rule (with filtering support)
        compiled_rules.each do |rule|
          # Check if this rule should be applied based on only/except options
          next unless valid_mapping?(rule, options)

          apply_rule(root, rule, model_instance, options)
        end

        if ENV["DEBUG_KEYED_COLLECTION"]
          puts "=== TRANSFORM COMPLETE ==="
          puts "root.children.count: #{root.children.count}"
          root.children.each do |child|
            puts "  child key=#{child.key.inspect}, value=#{child.value.inspect}, to_hash=#{child.to_hash.inspect}"
          end
          puts "root.to_hash: #{root.to_hash.inspect}"
        end

        root
      end

      private

      # Apply a single transformation rule
      #
      # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
      # @param rule [CompiledRule] The rule to apply
      # @param model_instance [Object] The model instance
      # @param options [Hash] Transformation options
      def apply_rule(parent, rule, model_instance, options)
        # DEBUG for keyed collections
        if ENV["DEBUG_KEYED_COLLECTION"]
          puts "apply_rule: #{rule.serialized_name}, collection?: #{rule.collection?}"
          if rule.collection?
            puts "  collection_info: #{rule.collection_info.inspect}"
            puts "  child_mappings: #{rule.collection_info && rule.collection_info[:child_mappings].inspect}"
          end
        end

        # Handle custom serialization methods (e.g., with: { to: ... })
        if rule.has_custom_methods? && rule.custom_methods[:to]
          # Call custom method which directly modifies the parent element
          return model_instance.send(rule.custom_methods[:to],
                                     model_instance, parent)
        end

        # Handle delegation - extract value from delegated object
        delegate = rule.option(:delegate)
        if delegate
          # Get the delegated object
          delegated_object = model_instance.public_send(delegate)

          # Initialize delegated object if nil/uninitialized (like legacy does)
          if delegated_object.nil? || Lutaml::Model::Utils.uninitialized?(delegated_object)
            # Get the delegate attribute from model to create a new instance
            delegate_attr = model_class.attributes(register_id)&.[](delegate)
            if delegate_attr
              delegated_object = delegate_attr.type(register_id).new
              model_instance.public_send(:"#{delegate}=", delegated_object)
            end
          end

          # Extract value from delegated object
          value = delegated_object&.public_send(rule.attribute_name)
        else
          # Get attribute value directly
          value = model_instance.public_send(rule.attribute_name)
        end

        # Handle raw mapping (map_all directive)
        # Raw mappings parse the stored content and merge it directly into the parent
        if rule.option(:mapping_type) == :raw
          return handle_raw_mapping(parent, value, options)
        end

        # Check if value should be skipped
        skip_result = should_skip_value?(value, rule, model_instance,
                                         delegate)

        return if skip_result

        # Apply export transformation if present
        if rule.value_transformer
          value = rule.transform_value(value, :export)
        end

        # Track if value was converted due to render options
        # This prevents value_map from overriding the explicit render directives
        converted_from_empty_to_nil = false
        converted_from_nil_to_empty = false

        # Apply value_map transformation (e.g., empty -> nil, nil -> empty, etc.)
        value_map = rule.option(:value_map) || {}
        if value.nil?
          # Check render_nil option before value_map
          render_nil = rule.option(:render_nil)
          if render_nil == :as_empty
            # Convert nil to empty collection - handled in create_collection_element
            # Don't convert here, just track it
            converted_from_nil_to_empty = true
          end

          # Only check value_map if we didn't already convert the value
          unless converted_from_nil_to_empty
            to_nil = value_map[:to]&.[](:nil)
            if to_nil == :empty
              value = ""
            elsif %i[omit omitted].include?(to_nil)
              # This should have been caught by should_skip_value?, but handle it here too
              return
            end
          end
        elsif Lutaml::Model::Utils.empty?(value)
          # Check render_empty option for empty collections
          render_empty = rule.option(:render_empty)
          if render_empty == :as_nil
            # Convert empty collection to nil for serialization
            # Track this conversion so value_map nil-check doesn't override it
            value = nil
            converted_from_empty_to_nil = true
          end

          # Only check value_map if we didn't already convert the value
          unless converted_from_empty_to_nil
            to_empty = value_map[:to]&.[](:empty)
            if to_empty == :nil
              value = nil
            elsif %i[omit omitted].include?(to_empty)
              # This should have been caught by should_skip_value?, but handle it here too
              return
            end
          end
        elsif Lutaml::Model::Utils.uninitialized?(value)
          to_omitted = value_map[:to]&.[](:omitted)
          if to_omitted == :nil
            value = nil
          elsif to_omitted == :empty
            value = ""
          elsif %i[omit omitted].include?(to_omitted)
            # This should have been caught by should_skip_value?, but handle it here too
            return
          end
        end

        # Create element for this attribute
        if rule.collection?
          # Handle collection
          create_collection_element(parent, rule, value, options,
                                    converted_from_empty_to_nil: converted_from_empty_to_nil,
                                    converted_from_nil_to_empty: converted_from_nil_to_empty)
        else
          # Handle single value
          create_value_element(parent, rule, value, options)
        end
      end

      # Check if value should be skipped based on render options
      #
      # Delegates to the shared RenderPolicy module for consistent
      # behavior across XML and KeyValue formats.
      #
      # @param value [Object] The value to check
      # @param rule [CompiledRule] The rule
      # @param model_instance [Object] The model instance
      # @param delegate [Symbol, nil] The delegate attribute name if present
      # @return [Boolean] true if should skip
      def should_skip_value?(value, rule, model_instance, delegate = nil)
        if delegate
          delegate_obj = model_instance.public_send(delegate)
          should_skip_delegated_value?(value, rule, delegate_obj)
        else
          super(value, rule, model_instance)
        end
      end

      # Create a collection element
      #
      # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
      # @param rule [CompiledRule] The rule
      # @param collection [Array] The collection value
      # @param options [Hash] Options
      # @param converted_from_empty_to_nil [Boolean] True if value was converted from empty to nil
      # @param converted_from_nil_to_empty [Boolean] True if value should be converted from nil to empty
      def create_collection_element(parent, rule, collection, options,
converted_from_empty_to_nil: false, converted_from_nil_to_empty: false)
        # Handle nil collection - skip if nil unless should render
        if collection.nil?
          render_nil = rule.option(:render_nil)
          if render_nil == :as_empty || converted_from_nil_to_empty
            # Render as empty collection
            element = Lutaml::KeyValue::DataModel::Element.new(
              rule.serialized_name, []
            )
            parent.add_child(element)
          elsif render_nil == :as_blank
            # Render as blank collection (single empty string element)
            # This is used for XML serialization to create <items/>
            element = Lutaml::KeyValue::DataModel::Element.new(
              rule.serialized_name, [""]
            )
            parent.add_child(element)
          elsif should_render_nil?(rule) || converted_from_empty_to_nil
            # Render nil collection as nil value
            # converted_from_empty_to_nil is true when render_empty: :as_nil was applied
            element = Lutaml::KeyValue::DataModel::Element.new(
              rule.serialized_name, nil
            )
            parent.add_child(element)
          else
            # Skip nil collection
          end
          return
        end

        # Convert to array for consistent handling
        items = Array(collection)

        # Check if this has root_mappings - merge directly into parent
        root_mappings = rule.option(:root_mappings)
        if root_mappings
          # For root_mappings, the collection items are keyed and merged directly into parent
          # Find the attribute to use as key
          key_attribute = root_mappings.key(:key)
          # Find the attribute to use as value (optional - if not provided, serialize all attributes)
          value_attribute = root_mappings.key(:value)

          # Initialize parent's value as a hash if it's nil
          parent.value ||= {} if parent.value.nil?

          # Case 1: Both key and value attributes specified
          if key_attribute && value_attribute
            items.each do |item|
              next if item.nil?

              # Get the key value from the item
              key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil
              next if key_value.nil?

              # Get the value from the item
              attr_value = item.respond_to?(value_attribute) ? item.public_send(value_attribute) : nil
              next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

              # For the value, we need to transform it appropriately
              # First, check if it's a single nested model
              item_class = item.class
              attr_def = item_class.attributes(register_id)&.[](value_attribute)

              if attr_def && attr_value.is_a?(Lutaml::Model::Serialize)
                # Single nested model - transform it to a hash
                attr_type = attr_def.type(register_id)
                if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
                  # Get the mapping for the value's class
                  value_class_mapping = attr_value.class.mappings_for(format,
                                                                      register_id)

                  # Build a transformation for the value's class
                  value_transformation = self.class.new(attr_value.class,
                                                        value_class_mapping, format, register)

                  # Transform the value to a KeyValueElement
                  value_root = value_transformation.transform(attr_value,
                                                              options)
                  value_hash = value_root.to_hash

                  # Extract the value from the __root__ wrapper
                  parent.value[key_value.to_s] = value_hash["__root__"]
                  next
                end
              end

              # Check if it's a collection
              if attr_value.is_a?(Array) || attr_value.is_a?(Lutaml::Model::Collection)
                # Get the attribute definition for the value attribute from the item's class
                item_class = item.class
                attr_def = item_class.attributes(register_id)&.[](value_attribute)
                next unless attr_def

                # Get the type of items in the collection
                item_type = attr_def.type(register_id)

                # Get the child transformation for the collection item type
                if item_type.is_a?(Class) && item_type < Lutaml::Model::Serialize
                  # Create a temporary parent KeyValueElement to hold the collection
                  temp_parent = Lutaml::KeyValue::DataModel::Element.new("__temp__")

                  # Convert to array
                  coll_items = Array(attr_value)

                  # Get the mapping for the item's class
                  item_class_mapping = item_class.mappings_for(format,
                                                               register_id)

                  # Build a temporary transformation for the item's class
                  item_class_transformation = self.class.new(item_class,
                                                             item_class_mapping, format, register)

                  # Find the rule for the value_attribute in the item's class mapping
                  item_rule = item_class_transformation.send(:compiled_rules).find do |r|
                    r.attribute_name == value_attribute
                  end

                  if item_rule&.collection_info && item_rule.collection_info[:child_mappings]
                    # Use the keyed collection handling
                    child_mappings = item_rule.collection_info[:child_mappings]
                    coll_key_attr = keyed_collection_key_attribute(child_mappings)

                    if coll_key_attr
                      # Create a keyed collection directly
                      create_keyed_collection_element(temp_parent, item_rule,
                                                      coll_items, coll_key_attr, child_mappings, options)
                    else
                      create_array_collection_element(temp_parent, item_rule,
                                                      coll_items, options)
                    end
                  elsif item_rule
                    # No child_mappings - serialize as array
                    create_array_collection_element(temp_parent, item_rule,
                                                    coll_items, options)
                  end

                  # Extract the value from temp_parent
                  temp_hash = temp_parent.to_hash
                  inner_value = temp_hash["__temp__"]
                  coll_value = inner_value&.[](value_attribute.to_s) if inner_value

                  parent.value[key_value.to_s] = coll_value
                  next
                end
              end

              # Fallback: just use the value directly
              parent.value[key_value.to_s] = attr_value
            end
          # Case 2: Only key attribute specified - serialize all other attributes
          elsif key_attribute
            items.each do |item|
              next if item.nil?

              # Get the key value from the item
              key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil
              next if key_value.nil?

              # Serialize all attributes except the key
              item_hash = {}
              item_class = item.class

              # Get the mapping for the item's class to find serialized names
              if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
                item_class_mapping = item_class.mappings_for(format,
                                                             register_id)

                item_class.attributes(register_id).each do |attr_name, attr_def|
                  # Skip the key attribute since it's used as the hash key
                  next if attr_name == key_attribute

                  attr_value = item.public_send(attr_name)
                  next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

                  # Serialize the attribute value
                  serialized_value = serialize_collection_item_value(
                    attr_value, attr_def, options
                  )

                  # Determine the path for this attribute based on root_mappings
                  # root_mappings format: { attr_name => path_spec }
                  # where path_spec can be:
                  # - :key (used as hash key, already skipped above)
                  # - "string" (single key, use the string)
                  # - [:path, :to, :nested] (array of path segments)
                  path_spec = root_mappings[attr_name]

                  # Use the path_spec if present, otherwise use the serialized name from mapping
                  if path_spec
                    if path_spec.is_a?(Array)
                      # Build nested structure: [:path, :to, :nested] -> item_hash["path"]["to"]["nested"] = value
                      current = item_hash
                      path_spec[0...-1].each do |key|
                        key_str = key.to_s
                        current[key_str] ||= {}
                        current = current[key_str]
                      end
                      current[path_spec.last.to_s] = serialized_value
                    elsif path_spec == :key
                      # Skip - key is used as the hash key
                      next
                    else
                      # Use the path_spec as a single key
                      item_hash[path_spec.to_s] = serialized_value
                    end
                  else
                    # No path_spec in root_mappings - use the serialized name from the mapping
                    serialized_name = attr_name.to_s
                    if item_class_mapping
                      mapping_rule = item_class_mapping.mappings.find do |m|
                        m.to == attr_name
                      end
                      serialized_name = mapping_rule.name.to_s if mapping_rule&.name
                    end

                    item_hash[serialized_name] = serialized_value
                  end
                end
              end

              parent.value[key_value.to_s] = item_hash unless item_hash.empty?
            end
          end

          return
        end

        # Check if this is a keyed collection (map_key feature)
        child_mappings = rule.collection_info && rule.collection_info[:child_mappings]
        key_attribute = keyed_collection_key_attribute(child_mappings)

        if key_attribute
          # Serialize as hash keyed by the key attribute
          create_keyed_collection_element(parent, rule, items, key_attribute,
                                          child_mappings, options)
        else
          # Serialize as array (default)
          create_array_collection_element(parent, rule, items, options)
        end
      end

      # Create a keyed collection element (map_key feature)
      #
      # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
      # @param rule [CompiledRule] The rule
      # @param items [Array] The collection items
      # @param key_attribute [Symbol] The attribute to use as hash key
      # @param child_mappings [Hash] The child mappings configuration
      # @param options [Hash] Options
      def create_keyed_collection_element(parent, rule, items, key_attribute,
child_mappings, options)
        # Create hash to hold keyed items
        keyed_hash = {}

        # Check if there's a value mapping (map_value as_attribute: :name)
        # This means we should serialize just the specified attribute value, not the full item hash
        value_attribute = nil
        child_mappings&.each do |attr_name, mapping_type|
          value_attribute = attr_name if mapping_type == :value
        end

        if ENV["DEBUG_KEYED_COLLECTION"]
          puts "create_keyed_collection_element: items.count=#{items.count}, key_attribute=#{key_attribute}, value_attribute=#{value_attribute.inspect}"
        end

        items.each do |item|
          # Get the key value from the item
          key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil

          if ENV["DEBUG_KEYED_COLLECTION"]
            puts "  item: #{item.inspect}, key_value=#{key_value.inspect}"
          end

          next if key_value.nil?

          # If there's a value mapping, serialize just that attribute value
          if value_attribute
            attr_value = item.respond_to?(value_attribute) ? item.public_send(value_attribute) : nil
            next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

            # Get the attribute definition for proper serialization
            attr_def = nil
            item_class = item.class
            if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
              attr_def = item_class.attributes(register_id)&.[](value_attribute)
            end

            # Serialize the attribute value
            serialized_value = if attr_def
                                 serialize_collection_item_value(attr_value,
                                                                 attr_def, options)
                               else
                                 attr_value
                               end

            unless serialized_value.nil?
              keyed_hash[key_value.to_s] =
                serialized_value
            end
          else
            # No value mapping - serialize all attributes as a hash
            item_hash = {}

            # Check if child_mappings only contains :key/:value (no nested paths)
            # In that case, we should also serialize other attributes not in child_mappings
            has_nested_paths = child_mappings&.any? do |_, path_spec|
              path_spec.is_a?(Array)
            end

            # Use child_mappings to determine where each attribute goes in the nested hash
            if child_mappings && (has_nested_paths || child_mappings.any? do |_, path_spec|
              path_spec != :key && path_spec != :value
            end)
              # child_mappings format: { attr_name => path_spec }
              # where path_spec can be:
              # - :key (used as hash key, already handled)
              # - :value (use the value directly)
              # - [:path, :to, :nested] (nested path)
              # - :simple (single key, same as attr_name)

              if ENV["DEBUG_KEYED_COLLECTION"]
                puts "  Using child_mappings: #{child_mappings.inspect}"
              end

              child_mappings.each do |attr_name, path_spec|
                # Skip :key mappings - they're used as the hash key
                next if path_spec == :key
                # Skip :value mappings - handled separately
                next if path_spec == :value

                # Get the attribute value
                attr_value = item.respond_to?(attr_name) ? item.public_send(attr_name) : nil

                if ENV["DEBUG_KEYED_COLLECTION"]
                  puts "    #{attr_name}: path_spec=#{path_spec.inspect}, attr_value=#{attr_value.inspect}"
                end

                next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

                # Get the attribute definition for proper serialization
                attr_def = nil
                item_class = item.class
                if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
                  attr_def = item_class.attributes(register_id)&.[](attr_name)
                end

                # Serialize the attribute value
                serialized_value = if attr_def
                                     serialize_collection_item_value(
                                       attr_value, attr_def, options
                                     )
                                   else
                                     attr_value
                                   end

                next if serialized_value.nil?

                # Build the nested hash structure based on path_spec
                # path_spec can be:
                # - [:path, :to, :nested] - array of path segments
                # - :simple - single key
                if path_spec.is_a?(Array)
                  # Build nested structure: [:path, :to, :nested] -> item_hash["path"]["to"]["nested"] = value
                  current = item_hash
                  path_spec[0...-1].each do |key|
                    key_str = key.to_s
                    current[key_str] ||= {}
                    current = current[key_str]
                  end
                  current[path_spec.last.to_s] = serialized_value
                else
                  # Single key - use attr_name as key
                  item_hash[attr_name.to_s] = serialized_value
                end
              end
            end

            # Always serialize all attributes (as fallback) for keyed collections
            # This handles the case where child_mappings only has :key mapping
            item_class = item.class
            if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
              if ENV["DEBUG_KEYED_COLLECTION"]
                puts "  item_class.attributes(#{register_id}): #{item_class.attributes(register_id).inspect}"
              end
              item_class.attributes(register_id).each do |attr_name, attr_def|
                # Skip the key attribute since it's used as the hash key
                next if attr_name == key_attribute
                # Skip attributes already processed by child_mappings
                next if child_mappings&.key?(attr_name)

                attr_value = item.public_send(attr_name)

                if ENV["DEBUG_KEYED_COLLECTION"]
                  puts "    #{attr_name}: attr_value=#{attr_value.inspect}"
                end

                next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

                # Serialize the attribute value
                serialized_value = serialize_collection_item_value(attr_value,
                                                                   attr_def, options)
                if ENV["DEBUG_KEYED_COLLECTION"]
                  puts "      serialized_value=#{serialized_value.inspect}"
                end
                unless serialized_value.nil?
                  item_hash[attr_name.to_s] =
                    serialized_value
                end
              end
            end

            if ENV["DEBUG_KEYED_COLLECTION"]
              puts "  item_hash: #{item_hash.inspect}"
            end

            # Add to keyed hash
            keyed_hash[key_value.to_s] = item_hash unless item_hash.empty?
          end
        end

        if ENV["DEBUG_KEYED_COLLECTION"]
          puts "  keyed_hash: #{keyed_hash.inspect}"
        end

        # Create element with hash value
        element = Lutaml::KeyValue::DataModel::Element.new(
          rule.serialized_name, keyed_hash
        )

        if ENV["DEBUG_KEYED_COLLECTION"]
          puts "  element created: key=#{element.key.inspect}, value=#{element.value.inspect}, children.count=#{element.children.count}"
          puts "  element.to_hash: #{element.to_hash.inspect}"
        end

        parent.add_child(element)
      end

      # Create an array collection element (default)
      #
      # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
      # @param rule [CompiledRule] The rule
      # @param items [Array] The collection items
      # @param options [Hash] Options
      def create_array_collection_element(parent, rule, items, options)
        # Create an element for the collection
        coll_element = Lutaml::KeyValue::DataModel::Element.new(rule.serialized_name)

        if items.empty?
          # For empty collections, set value to empty array explicitly
          coll_element.value = []
        else
          # Add each item as a child
          items.each do |item|
            child_value = create_value_for_item(rule, item, options)
            # Use explicit nil check - `if child_value` would fail for boolean false!
            coll_element.add_child(child_value) unless child_value.nil?
          end
        end

        # Always add collection element
        parent.add_child(coll_element)
      end

      # Get the key attribute for a keyed collection from child_mappings
      #
      # @param child_mappings [Hash] The child mappings (e.g., { id: :key })
      # @return [Symbol, nil] The attribute name to use as key, or nil
      def keyed_collection_key_attribute(child_mappings)
        return nil unless child_mappings

        # Find the attribute mapped to :key
        child_mappings.each do |attr_name, mapping|
          return attr_name.to_sym if mapping == :key
        end

        nil
      end

      # Serialize a collection item value (for keyed collections)
      #
      # @param value [Object] The value to serialize
      # @param attr_def [Attribute] The attribute definition
      # @param options [Hash] Options
      # @return [Object] The serialized value
      def serialize_collection_item_value(value, attr_def, options)
        return nil if value.nil? || Lutaml::Model::Utils.uninitialized?(value)

        # Check if this is a collection attribute
        attr_type = attr_def.type(register_id)
        if attr_def.collection?
          # For collections, check if it's a collection of Serialize models
          if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
            # Create child transformation for the item type
            mapping = attr_type.mappings_for(format, register_id)
            child_transformation = self.class.new(attr_type, mapping, format,
                                                  register)

            # Serialize each item in the collection
            items = Array(value)
            if items.empty?
              []
            else
              # For keyed collections (with child_mappings), serialize as hash
              # For regular collections, serialize as array
              # We need to check if the mapping has child_mappings for this attribute
              # Since we don't have direct access to the parent mapping here,
              # serialize as array for now (default behavior)
              items.map do |item|
                child_root = child_transformation.transform(item, options)
                child_hash = child_root.to_hash
                child_hash["__root__"]
              end
            end
          else
            # Primitive collection - return as-is (already an array)
            value
          end
        elsif attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
          # Single value - check if it's a nested model
          mapping = attr_type.mappings_for(format, register_id)
          child_transformation = self.class.new(attr_type, mapping, format,
                                                register)
          child_root = child_transformation.transform(value,
                                                      options)
          child_hash = child_root.to_hash
          child_hash["__root__"]
        # Use the transformation to serialize the nested model
        elsif attr_type.respond_to?(:new)
          # Serialize primitive value
          wrapped_value = attr_type.new(value)
          wrapped_value.send(:"to_#{format}")
        else
          value
        end
      end

      # Create a value element
      #
      # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
      # @param rule [CompiledRule] The rule
      # @param value [Object] The value
      # @param options [Hash] Options
      def create_value_element(parent, rule, value, options)
        return if value.nil? && !should_render_nil?(rule)

        child_value = create_value_for_item(rule, value, options)

        # Use explicit nil check - `if child_value` would fail for boolean false!
        if child_value.nil?
          # For nil values with render_nil options, create the appropriate element
          if value.nil?
            render_nil = rule.option(:render_nil)
            if render_nil == :as_empty
              # Render as empty collection
              element = Lutaml::KeyValue::DataModel::Element.new(
                rule.serialized_name, []
              )
              parent.add_child(element)
            elsif should_render_nil?(rule)
              # Render as nil
              element = Lutaml::KeyValue::DataModel::Element.new(
                rule.serialized_name, nil
              )
              parent.add_child(element)
            end
          elsif Lutaml::Model::Utils.uninitialized?(value)
            # Handle uninitialized values - check value_map for directive
            value_map = rule.option(:value_map) || {}
            to_omitted = value_map[:to]&.[](:omitted)

            if to_omitted == :nil
              # Render as nil
              element = Lutaml::KeyValue::DataModel::Element.new(
                rule.serialized_name, nil
              )
              parent.add_child(element)
            elsif to_omitted == :empty
              # Render as empty string
              element = Lutaml::KeyValue::DataModel::Element.new(
                rule.serialized_name, ""
              )
              parent.add_child(element)
            end
          end
          # If child_value is nil but original value was not nil or uninitialized,
          # it means the nested model serialized to empty - skip it
        else
          element = Lutaml::KeyValue::DataModel::Element.new(
            rule.serialized_name, child_value
          )
          parent.add_child(element)
        end
      end

      # Create value for an item (handles nested models and primitives)
      #
      # @param rule [CompiledRule] The rule
      # @param value [Object] The value
      # @param options [Hash] Options
      # @return [Object] The value (could be Hash, primitive, or KeyValueElement)
      def create_value_for_item(rule, value, options)
        return nil if value.nil?

        # Check if this is a nested model
        is_nested_model = rule.attribute_type.is_a?(Class) &&
          rule.attribute_type < Lutaml::Model::Serialize

        if is_nested_model
          # Validate that value matches the expected type
          # There are three valid cases:
          # 1. attribute_type is a mapper class (has model method) and value is an instance of that model
          # 2. attribute_type is a regular Serializable class and value is an instance of it (or subclass)
          # 3. value's class is a registered type substitution for attribute_type
          context = Lutaml::Model::GlobalContext.context(register_id)
          subs = context.substitution_for(rule.attribute_type)
          uses_type_substitution = subs.any? { |s| s.to_type == value.class }

          if rule.attribute_type.respond_to?(:model) && rule.attribute_type.model
            # Mapper class: value should be an instance of the mapped model
            # or a valid substituted type
            unless value.is_a?(rule.attribute_type.model) || uses_type_substitution
              msg = "attribute '#{rule.attribute_name}' value is a '#{value.class}' but should be a '#{rule.attribute_type.model}'"
              raise Lutaml::Model::IncorrectModelError, msg
            end
          else
            # Regular Serializable class: value should be a Serialize instance
            # or a valid substituted type
            unless value.is_a?(Lutaml::Model::Serialize) || uses_type_substitution
              msg = "attribute '#{rule.attribute_name}' value is a '#{value.class}' but should be a kind of 'Lutaml::Model::Serialize'"
              raise Lutaml::Model::IncorrectModelError, msg
            end
          end

          # Use the actual runtime type for polymorphism support
          # If value is a subclass of the declared type, use its mappings instead
          # Also handle type substitution the same way
          actual_type = value.class
          uses_polymorphism = (actual_type != rule.attribute_type &&
            actual_type < rule.attribute_type) || uses_type_substitution

          # Get child transformation - may be cached or need to create
          child_transformation = rule.child_transformation

          # If not cached (e.g., due to cycles) or using polymorphism, create it now
          if !child_transformation || uses_polymorphism
            # For polymorphic types, use the actual runtime type's mappings
            type_for_mapping = uses_polymorphism ? actual_type : rule.attribute_type
            mapping = type_for_mapping.mappings_for(format, register_id)
            child_transformation = self.class.new(type_for_mapping, mapping,
                                                  format, register)
          end

          if child_transformation
            child_root = child_transformation.transform(value, options)
            # Return the hash representation of the child
            # Remove the __root__ wrapper and return just the content
            child_hash = child_root.to_hash
            result = child_hash["__root__"]
            # If the nested model serialized to empty hash, return nil
            # This allows render_nil: false to work correctly for nested models
            result.nil? || result.empty? ? nil : result
          else
            # Fallback: serialize as primitive
            serialize_value(value, rule)
          end
        else
          # Serialize primitive value
          serialize_value(value, rule)
        end
      end

      # Check if nil should be rendered
      #
      # @param rule [CompiledRule] The rule
      # @return [Boolean]
      def should_render_nil?(rule)
        render_nil = rule.option(:render_nil)
        return true if render_nil == :as_nil
        return true if render_nil == true # Treat true the same as :as_nil

        value_map = rule.option(:value_map) || {}

        # Check value_map[:to][:nil] for the to directive (serialization)
        # - :nil means render as nil (don't omit)
        # - :empty means render as empty string (don't omit)
        # - :omit or :omitted means omit the value
        to_nil = value_map[:to]&.[](:nil)
        if to_nil
          # If to directive is set, check if it's :omit or :omitted
          result = !%i[omit omitted].include?(to_nil)
        elsif value_map.key?(:nil)
          # Legacy support: check top-level :nil key
          result = value_map[:nil] != :omit
        else
          # Check if empty or omitted values are being transformed to nil
          # If so, they should be rendered
          to_empty = value_map[:to]&.[](:empty)
          to_omitted = value_map[:to]&.[](:omitted)
          result = to_empty == :nil || to_omitted == :nil
        end

        result
      end

      # Handle raw mapping (map_all directive)
      #
      # Raw mappings parse the stored content (JSON/YAML/TOML string) and merge it
      # directly into the parent element, rather than creating a child element.
      #
      # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
      # @param value [String] The raw content (JSON/YAML/TOML string)
      # @param options [Hash] Options
      def handle_raw_mapping(parent, value, options)
        return if value.nil? || Lutaml::Model::Utils.uninitialized?(value)
        return if Lutaml::Model::Utils.empty?(value)

        # Get the adapter for the current format and parse the raw content
        adapter = Lutaml::Model::Config.adapter_for(format)
        parsed_content = adapter.parse(value, options)

        # Merge the parsed content into the parent element
        # For each key-value pair in the parsed content, add as a child element
        if parsed_content.is_a?(::Hash)
          parsed_content.each do |key, val|
            element = Lutaml::KeyValue::DataModel::Element.new(key.to_s, val)
            parent.add_child(element)
          end
        elsif parsed_content.is_a?(::Array)
          # If the parsed content is an array, we can't merge it directly
          # This shouldn't happen with valid map_all usage, but handle it gracefully
          element = Lutaml::KeyValue::DataModel::Element.new("__root__",
                                                             parsed_content)
          parent.add_child(element)
        end
      end

      # Serialize a value to appropriate representation
      #
      # @param value [Object] The value to serialize
      # @param rule [CompiledRule] The rule
      # @return [Object] Serialized value
      def serialize_value(value, rule)
        return nil if value.nil?
        return nil if Lutaml::Model::Utils.uninitialized?(value)

        # For Reference types, use attribute's serialize method which handles reference_key extraction
        # Check the attribute's unresolved_type to match the condition in Attribute#serialize
        # Try to get attribute from model_class (with register first, then without)
        attr = model_class.attributes(register_id)&.[](rule.attribute_name)
        attr ||= model_class.attributes&.[](rule.attribute_name)

        if attr && attr.unresolved_type == Lutaml::Model::Type::Reference
          return attr.serialize(value, format, register_id, {})
        end

        # Validate that value is an instance of the expected Serializable type
        # When attribute_type is a Serializable class, value must be an instance of that class
        if rule.attribute_type.is_a?(Class) && rule.attribute_type < Lutaml::Model::Serialize
          unless value.is_a?(rule.attribute_type)
            msg = "attribute '#{rule.attribute_name}' value is a '#{value.class}' but should be a '#{rule.attribute_type}'"
            raise Lutaml::Model::IncorrectModelError, msg
          end

          # Value is a valid Serialize instance - serialize it using its own to_#{format} method
          return value.send(:"to_#{format}")
        end

        # Wrap value in type and call to_#{format} instance method (like legacy Attribute#serialize_value)
        # This allows custom type subclasses to override to_json, to_yaml, etc.
        if rule.attribute_type.respond_to?(:new)
          wrapped_value = rule.attribute_type.new(value)
          wrapped_value.send(:"to_#{format}")
        else
          value
        end
      end
    end
  end
end
