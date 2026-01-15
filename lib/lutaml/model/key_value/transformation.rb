# frozen_string_literal: true

require_relative "../transformation"
require_relative "../compiled_rule"
require_relative "../key_value_data_model"

module Lutaml
  module Model
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
        private

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
            attr_name = if mapping_rule.name && model_class.attributes(register&.id)&.key?(mapping_rule.name.to_sym)
                          mapping_rule.name.to_sym
                        elsif mapping_rule.from.is_a?(String) && model_class.attributes(register&.id)&.key?(mapping_rule.from.to_sym)
                          mapping_rule.from.to_sym
                        end
          end

          # For custom methods without an inferred attribute, use a placeholder
          # The custom method will handle all serialization logic
          if attr_name.nil? && !custom_methods.empty?
            # Use serialized name as placeholder for attribute name
            # The custom method handles everything, so we don't need a real attribute
            attr_name = mapping_rule.name&.to_sym || :__custom_method__

            # Create a dummy attribute type for custom methods
            attr = nil
            attr_type = nil
            child_transformation = nil
            collection_info = nil
            value_transformer = nil
          else
            return nil unless attr_name

            # For delegated attributes, get attribute from delegated object's class
            if delegate
              # Get the delegate attribute from model to find the delegated class
              delegate_attr = model_class.attributes(register&.id)&.[](delegate)
              return nil unless delegate_attr

              # Get the delegated class type
              delegated_class = delegate_attr.type(register&.id)
              return nil unless delegated_class

              # Get the actual attribute from the delegated class
              attr = delegated_class.attributes&.[](attr_name)
              return nil unless attr
            else
              # Get attribute definition from model class
              attr = model_class.attributes(register&.id)&.[](attr_name)
              return nil unless attr
            end

            # Get attribute type
            attr_type = attr.type(register&.id)

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

                                info[:child_mappings] = child_mappings_value if child_mappings_value
                                info
                              end

            # Build value transformer (use delegate_attr for delegated attributes)
            value_transformer = build_value_transformer(mapping_rule, delegate ? delegate_attr : attr)
          end

          # Access value_map directly
          value_map = mapping_rule.instance_variable_get(:@value_map)

          # Get serialized name (key name in output)
          serialized_name = if mapping_rule.name != nil
                              mapping_rule.name.to_s
                            elsif mapping_rule.from != nil
                              # For compatibility with multiple_mappings
                              mapping_rule.from.is_a?(Array) ? mapping_rule.from.first.to_s : mapping_rule.from.to_s
                            else
                              attr_name.to_s
                            end

          CompiledRule.new(
            attribute_name: attr_name,
            serialized_name: serialized_name,
            attribute_type: attr_type,
            child_transformation: child_transformation,
            value_transformer: value_transformer,
            collection_info: collection_info,
            mapping_type: :key_value,
            render_nil: mapping_rule.render_nil,
            render_default: mapping_rule.render_default,
            render_empty: mapping_rule.render_empty,
            value_map: value_map,
            custom_methods: custom_methods,
            delegate: delegate
          )
        end

        # Build child transformation for nested model
        #
        # @param type_class [Class] The nested model class
        # @return [Transformation, nil] Child transformation or nil
        def build_child_transformation(type_class)
          return nil unless type_class.respond_to?(:mappings_for)

          # Get the mapping for the current format (not hardcoded to :json)
          mapping = type_class.mappings_for(format, register&.id)

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
        # @return [KeyValueDataModel::KeyValueElement] The root element
        def transform(model_instance, options = {})
          # For key-value formats, we typically don't have a named root
          # Instead, we create an anonymous root that holds all attributes
          root = KeyValueDataModel::KeyValueElement.new("__root__")

          # Apply each compiled rule (with filtering support)
          compiled_rules.each do |rule|
            # Check if this rule should be applied based on only/except options
            next unless valid_mapping?(rule, options)

            apply_rule(root, rule, model_instance, options)
          end

          if ENV['DEBUG_KEYED_COLLECTION']
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
        # @param parent [KeyValueDataModel::KeyValueElement] Parent element
        # @param rule [CompiledRule] The rule to apply
        # @param model_instance [Object] The model instance
        # @param options [Hash] Transformation options
        def apply_rule(parent, rule, model_instance, options)
          # DEBUG for keyed collections
          if ENV['DEBUG_KEYED_COLLECTION']
            puts "apply_rule: #{rule.serialized_name}, collection?: #{rule.collection?}"
            if rule.collection?
              puts "  collection_info: #{rule.collection_info.inspect}"
              puts "  child_mappings: #{rule.collection_info && rule.collection_info[:child_mappings].inspect}"
            end
          end
          # DEBUG
          if ENV['DEBUG_APPLY_RULE']
            puts "Applying rule: #{rule.serialized_name}, attr: #{rule.attribute_name.inspect}, delegate: #{rule.option(:delegate).inspect}, render_nil: #{rule.option(:render_nil).inspect}"
          end

          # Handle custom serialization methods (e.g., with: { to: ... })
          if rule.has_custom_methods? && rule.custom_methods[:to]
            # Call custom method which directly modifies the parent element
            return model_instance.send(rule.custom_methods[:to], model_instance, parent)
          end

          # Handle delegation - extract value from delegated object
          delegate = rule.option(:delegate)
          if delegate
            # Get the delegated object
            delegated_object = model_instance.public_send(delegate)

            # Initialize delegated object if nil/uninitialized (like legacy does)
            if delegated_object.nil? || Lutaml::Model::Utils.uninitialized?(delegated_object)
              # Get the delegate attribute from model to create a new instance
              delegate_attr = model_class.attributes(register&.id)&.[](delegate)
              if delegate_attr
                delegated_object = delegate_attr.type(register&.id).new
                model_instance.public_send(:"#{delegate}=", delegated_object)
              end
            end

            # Extract value from delegated object
            value = delegated_object&.public_send(rule.attribute_name)
          else
            # Get attribute value directly
            value = model_instance.public_send(rule.attribute_name)
          end

          # DEBUG
          if ENV['DEBUG_APPLY_RULE']
            puts "  value: #{value.inspect}, will skip: #{should_skip_value?(value, rule, model_instance, delegate).inspect}"
          end

          # Check if value should be skipped
          return if should_skip_value?(value, rule, model_instance, delegate)

          # Apply export transformation if present
          if rule.value_transformer
            value = rule.transform_value(value, :export)
          end

          # Create element for this attribute
          if rule.collection?
            # Handle collection
            create_collection_element(parent, rule, value, options)
          else
            # Handle single value
            create_value_element(parent, rule, value, options)
          end

          # DEBUG
          if ENV['DEBUG_APPLY_RULE']
            puts "  After create, parent.children.count: #{parent.children.count}, parent.to_hash.inspect}"
          end
        end

        # Check if value should be skipped based on render options
        #
        # @param value [Object] The value to check
        # @param rule [CompiledRule] The rule
        # @param model_instance [Object] The model instance
        # @param delegate [Symbol, nil] The delegate attribute name if present
        # @return [Boolean] true if should skip
        def should_skip_value?(value, rule, model_instance, delegate = nil)
          attr_name = rule.attribute_name

          # For delegated attributes, check using_default? on the delegated object
          target_instance = if delegate
                              model_instance.public_send(delegate)
                            else
                              model_instance
                            end

          # Check render shortcuts FIRST
          # This ensures mutated collections with default values are still serialized
          if value.nil?
            render_nil = rule.option(:render_nil)
            return true if render_nil == :omit
            return false if render_nil == true  # true means DO render nil
            return false if render_nil == :as_nil  # :as_nil means DO render nil
            return false if render_nil == :as_empty  # :as_empty means render as empty collection

            # For false or unset, skip nil values
            value_map = rule.option(:value_map) || {}
            return value_map[:nil] == :omit || true
          elsif Lutaml::Model::Utils.empty?(value)
            render_empty = rule.option(:render_empty)
            return true if render_empty == :omit
            return false if render_empty == true  # true means DO render empty
            return true if render_empty == false  # false means skip empty

            # For unset, default to rendering empty values (legacy behavior)
            value_map = rule.option(:value_map) || {}
            return value_map[:empty] == :omit
          elsif Lutaml::Model::Utils.uninitialized?(value)
            value_map = rule.option(:value_map) || {}
            return value_map[:omitted] == :omit || true
          end

          # Skip if using default and render_default is false
          # But for collections, check if they were mutated (non-empty)
          if target_instance&.respond_to?(:using_default?) &&
             target_instance.using_default?(attr_name) &&
             !rule.option(:render_default)
            # For collections: if mutated to non-empty, serialize them
            # For scalars: skip if using default
            if rule.collection?
              return false unless Lutaml::Model::Utils.empty?(value)
            else
              return true
            end
          end

          false
        end

        # Create a collection element
        #
        # @param parent [KeyValueDataModel::KeyValueElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param collection [Array] The collection value
        # @param options [Hash] Options
        def create_collection_element(parent, rule, collection, options)
          # Handle nil collection - skip if nil unless should render
          if collection.nil?
            render_nil = rule.option(:render_nil)
            if render_nil == :as_empty
              # Render as empty collection
              element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name, [])
              parent.add_child(element)
              return
            elsif should_render_nil?(rule)
              # Render nil collection as nil value
              element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name, nil)
              parent.add_child(element)
              return
            else
              # Skip nil collection
              return
            end
          end

          # Convert to array for consistent handling
          items = Array(collection)

          # Check if this is a keyed collection (map_key feature)
          child_mappings = rule.collection_info && rule.collection_info[:child_mappings]
          key_attribute = keyed_collection_key_attribute(child_mappings)

          if key_attribute
            # Serialize as hash keyed by the key attribute
            create_keyed_collection_element(parent, rule, items, key_attribute, child_mappings, options)
          else
            # Serialize as array (default)
            create_array_collection_element(parent, rule, items, options)
          end
        end

        # Create a keyed collection element (map_key feature)
        #
        # @param parent [KeyValueDataModel::KeyValueElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param items [Array] The collection items
        # @param key_attribute [Symbol] The attribute to use as hash key
        # @param child_mappings [Hash] The child mappings configuration
        # @param options [Hash] Options
        def create_keyed_collection_element(parent, rule, items, key_attribute, child_mappings, options)
          # Create hash to hold keyed items
          keyed_hash = {}

          # Check if there's a value mapping (map_value as_attribute: :name)
          # This means we should serialize just the specified attribute value, not the full item hash
          value_attribute = nil
          if child_mappings
            child_mappings.each do |attr_name, mapping_type|
              value_attribute = attr_name if mapping_type == :value
            end
          end

          if ENV['DEBUG_KEYED_COLLECTION']
            puts "create_keyed_collection_element: items.count=#{items.count}, key_attribute=#{key_attribute}, value_attribute=#{value_attribute.inspect}"
          end

          items.each do |item|
            # Get the key value from the item
            key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil

            if ENV['DEBUG_KEYED_COLLECTION']
              puts "  item: #{item.inspect}, key_value=#{key_value.inspect}"
            end

            next if key_value.nil?

            # If there's a value mapping, serialize just that attribute value
          if value_attribute
            attr_value = item.respond_to?(value_attribute) ? item.public_send(value_attribute) : nil
            next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

            # Get the attribute definition for proper serialization
            attr_def = nil
            if item.class.respond_to?(:attributes)
              attr_def = item.class.attributes(register&.id)&.[](value_attribute)
            end

            # Serialize the attribute value
            if attr_def
              serialized_value = serialize_collection_item_value(attr_value, attr_def, options)
            else
              serialized_value = attr_value
            end

            keyed_hash[key_value.to_s] = serialized_value unless serialized_value.nil?
          else
            # No value mapping - serialize all attributes as a hash
            item_hash = {}

            # Use child_mappings to determine where each attribute goes in the nested hash
            if child_mappings
              # child_mappings format: { attr_name => path_spec }
              # where path_spec can be:
              # - :key (used as hash key, already handled)
              # - :value (use the value directly)
              # - [:path, :to, :nested] (nested path)
              # - :simple (single key, same as attr_name)

              if ENV['DEBUG_KEYED_COLLECTION']
                puts "  Using child_mappings: #{child_mappings.inspect}"
              end

              child_mappings.each do |attr_name, path_spec|
                # Skip :key mappings - they're used as the hash key
                next if path_spec == :key
                # Skip :value mappings - handled separately
                next if path_spec == :value

                # Get the attribute value
                attr_value = item.respond_to?(attr_name) ? item.public_send(attr_name) : nil

                if ENV['DEBUG_KEYED_COLLECTION']
                  puts "    #{attr_name}: path_spec=#{path_spec.inspect}, attr_value=#{attr_value.inspect}"
                end

                next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

                # Get the attribute definition for proper serialization
                attr_def = nil
                if item.class.respond_to?(:attributes)
                  attr_def = item.class.attributes(register&.id)&.[](attr_name)
                end

                # Serialize the attribute value
                if attr_def
                  serialized_value = serialize_collection_item_value(attr_value, attr_def, options)
                else
                  serialized_value = attr_value
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
            else
              # No child_mappings - serialize all attributes (fallback)
              item_class = item.class
              if item_class.respond_to?(:attributes)
                if ENV['DEBUG_KEYED_COLLECTION']
                  puts "  item_class.attributes(#{register&.id}): #{item_class.attributes(register&.id).inspect}"
                end
                item_class.attributes(register&.id).each do |attr_name, attr_def|
                  # Skip the key attribute since it's used as the hash key
                  next if attr_name == key_attribute

                  attr_value = item.public_send(attr_name)

                  if ENV['DEBUG_KEYED_COLLECTION']
                    puts "    #{attr_name}: attr_value=#{attr_value.inspect}"
                  end

                  next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

                  # Serialize the attribute value
                  serialized_value = serialize_collection_item_value(attr_value, attr_def, options)
                  if ENV['DEBUG_KEYED_COLLECTION']
                    puts "      serialized_value=#{serialized_value.inspect}"
                  end
                  item_hash[attr_name.to_s] = serialized_value unless serialized_value.nil?
                end
              end
            end

            if ENV['DEBUG_KEYED_COLLECTION']
              puts "  item_hash: #{item_hash.inspect}"
            end

            # Add to keyed hash
            keyed_hash[key_value.to_s] = item_hash unless item_hash.empty?
          end
          end

          if ENV['DEBUG_KEYED_COLLECTION']
            puts "  keyed_hash: #{keyed_hash.inspect}"
          end

          # Create element with hash value
          element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name, keyed_hash)

          if ENV['DEBUG_KEYED_COLLECTION']
            puts "  element created: key=#{element.key.inspect}, value=#{element.value.inspect}, children.count=#{element.children.count}"
            puts "  element.to_hash: #{element.to_hash.inspect}"
          end

          parent.add_child(element)
        end

        # Create an array collection element (default)
        #
        # @param parent [KeyValueDataModel::KeyValueElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param items [Array] The collection items
        # @param options [Hash] Options
        def create_array_collection_element(parent, rule, items, options)
          # Create an element for the collection
          coll_element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name)

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
          if attr_def.collection?
            # For collections, check if it's a collection of Serialize models
            attr_type = attr_def.type(register&.id)
            if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
              # Create child transformation for the item type
              mapping = attr_type.mappings_for(format, register&.id)
              child_transformation = self.class.new(attr_type, mapping, format, register)

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
          else
            # Single value - check if it's a nested model
            attr_type = attr_def.type(register&.id)
            if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
              # Use the transformation to serialize the nested model
              mapping = attr_type.mappings_for(format, register&.id)
              child_transformation = self.class.new(attr_type, mapping, format, register)
              child_root = child_transformation.transform(value, options)
              child_hash = child_root.to_hash
              child_hash["__root__"]
            else
              # Serialize primitive value
              if attr_type.respond_to?(:new)
                wrapped_value = attr_type.new(value)
                wrapped_value.send(:"to_#{format}")
              else
                value
              end
            end
          end
        end

        # Create a value element
        #
        # @param parent [KeyValueDataModel::KeyValueElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The value
        # @param options [Hash] Options
        def create_value_element(parent, rule, value, options)
          # DEBUG
          if ENV['DEBUG_APPLY_RULE']
            puts "  create_value_element: value.nil?=#{value.nil?}, should_render_nil?=#{should_render_nil?(rule)}"
          end

          return if value.nil? && !should_render_nil?(rule)

          child_value = create_value_for_item(rule, value, options)

          # DEBUG
          if ENV['DEBUG_APPLY_RULE']
            puts "  child_value: #{child_value.inspect}, child_value.nil?: #{child_value.nil?}"
          end

          # Use explicit nil check - `if child_value` would fail for boolean false!
          unless child_value.nil?
            element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name, child_value)
            parent.add_child(element)
          else
            # For nil values with render_nil options, create the appropriate element
            if value.nil?
              render_nil = rule.option(:render_nil)
              if render_nil == :as_empty
                # Render as empty collection
                element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name, [])
                parent.add_child(element)
              elsif should_render_nil?(rule)
                # Render as nil
                element = KeyValueDataModel::KeyValueElement.new(rule.serialized_name, nil)
                parent.add_child(element)
              end
            end
            # If child_value is nil but original value was not nil,
            # it means the nested model serialized to empty - skip it
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
            # Use the actual runtime type for polymorphism support
            # If value is a subclass of the declared type, use its mappings instead
            actual_type = value.class
            uses_polymorphism = actual_type != rule.attribute_type &&
                                  actual_type < rule.attribute_type

            # Get child transformation - may be cached or need to create
            child_transformation = rule.child_transformation

            # If not cached (e.g., due to cycles) or using polymorphism, create it now
            if !child_transformation || uses_polymorphism
              # For polymorphic types, use the actual runtime type's mappings
              type_for_mapping = uses_polymorphism ? actual_type : rule.attribute_type
              mapping = type_for_mapping.mappings_for(format, register&.id)
              child_transformation = self.class.new(type_for_mapping, mapping, format, register)
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
          return true if render_nil == true  # Treat true the same as :as_nil

          value_map = rule.option(:value_map) || {}

          # Only check value_map[:nil] if explicitly set
          # Otherwise, default to NOT rendering nil
          result = if value_map.key?(:nil)
                    value_map[:nil] != :omit
                  else
                    false  # Don't render nil by default
                  end

          # DEBUG
          if ENV['DEBUG_APPLY_RULE']
            puts "    should_render_nil?: render_nil=#{render_nil.inspect}, value_map.key?(:nil)=#{value_map.key?(:nil)}, value_map[:nil]=#{value_map[:nil].inspect}, result=#{result}"
          end

          result
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
          attr = model_class.attributes(register&.id)&.[](rule.attribute_name)
          attr ||= model_class.attributes&.[](rule.attribute_name)

          if attr && attr.unresolved_type == Lutaml::Model::Type::Reference
            return attr.serialize(value, format, register&.id, {})
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
end