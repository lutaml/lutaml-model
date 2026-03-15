# frozen_string_literal: true

module Lutaml
  module KeyValue
    class Transformation
      # Serializes collections for key-value formats.
      #
      # This is an independent class with explicit dependencies that can be
      # tested in isolation from Transformation.
      #
      # Handles:
      # - Array collections
      # - Keyed collections (map_key feature)
      # - Root mappings pattern
      # - render_nil and render_empty options
      #
      class CollectionSerializer
        include Lutaml::Model::RenderPolicy

        # @return [Symbol] The serialization format (:json, :yaml, :toml)
        attr_reader :format

        # @return [Symbol, nil] The register ID for attribute lookup
        attr_reader :register_id

        # @return [ValueSerializer] The value serializer for item serialization
        attr_reader :value_serializer

        # @return [Proc] Factory lambda for creating child transformations
        attr_reader :transformation_factory

        # Initialize the CollectionSerializer with explicit dependencies.
        #
        # @param format [Symbol] The serialization format
        # @param register_id [Symbol, nil] The register ID
        # @param value_serializer [ValueSerializer] The value serializer
        # @param transformation_factory [Proc] Factory lambda ->(type_class) { Transformation }
        def initialize(format:, register_id:, value_serializer:, transformation_factory:)
          @format = format
          @register_id = register_id
          @value_serializer = value_serializer
          @transformation_factory = transformation_factory
        end

        # Serialize a collection to elements.
        #
        # This is the main entry point for collection serialization.
        #
        # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
        # @param collection [Object] The collection to serialize
        # @param rule [CompiledRule] The compiled rule
        # @param options [Hash] Serialization options
        # @param converted_from_empty_to_nil [Boolean] Whether nil was converted from empty
        # @param converted_from_nil_to_empty [Boolean] Whether empty was converted from nil
        # @return [void]
        def serialize(parent, collection, rule, options = {},
                      converted_from_empty_to_nil: false,
                      converted_from_nil_to_empty: false)
          create_collection_element(parent, collection, rule, options,
                                    converted_from_empty_to_nil: converted_from_empty_to_nil,
                                    converted_from_nil_to_empty: converted_from_nil_to_empty)
        end

        # Serialize a keyed collection (map_key feature).
        #
        # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
        # @param items [Array] The collection items
        # @param rule [CompiledRule] The compiled rule
        # @param key_attribute [Symbol] The attribute to use as hash key
        # @param child_mappings [Hash] The child mappings configuration
        # @param options [Hash] Serialization options
        # @return [void]
        def serialize_keyed(parent, items, rule, key_attribute, child_mappings, options = {})
          create_keyed_collection_element(parent, rule, items, key_attribute, child_mappings, options)
        end

        # Serialize an array collection.
        #
        # @param parent [Lutaml::KeyValue::DataModel::Element] Parent element
        # @param items [Array] The collection items
        # @param rule [CompiledRule] The compiled rule
        # @param options [Hash] Serialization options
        # @return [void]
        def serialize_array(parent, items, rule, options = {})
          create_array_collection_element(parent, rule, items, options)
        end

        # Get the key attribute for a keyed collection from child_mappings.
        #
        # @param child_mappings [Hash] The child mappings (e.g., { id: :key })
        # @return [Symbol, nil] The attribute name to use as key, or nil
        def keyed_collection_key_attribute(child_mappings)
          return nil unless child_mappings

          child_mappings.each do |attr_name, mapping|
            return attr_name.to_sym if mapping == :key
          end

          nil
        end

        private

        # Create a collection element based on rule and collection.
        def create_collection_element(parent, collection, rule, options,
                                      converted_from_empty_to_nil: false,
                                      converted_from_nil_to_empty: false)
          if collection.nil?
            handle_nil_collection(parent, rule, converted_from_empty_to_nil,
                                  converted_from_nil_to_empty)
            return
          end

          items = Array(collection)

          root_mappings = rule.option(:root_mappings)
          if root_mappings
            handle_root_mappings(parent, items, rule, root_mappings, options)
            return
          end

          child_mappings = rule.collection_info && rule.collection_info[:child_mappings]
          key_attribute = keyed_collection_key_attribute(child_mappings)

          if key_attribute
            create_keyed_collection_element(parent, rule, items, key_attribute,
                                            child_mappings, options)
          else
            create_array_collection_element(parent, rule, items, options)
          end
        end

        # Handle nil collection based on render options.
        def handle_nil_collection(parent, rule, converted_from_empty_to_nil,
                                  converted_from_nil_to_empty)
          render_nil = rule.option(:render_nil)

          if render_nil == :as_empty || converted_from_nil_to_empty
            element = Lutaml::KeyValue::DataModel::Element.new(rule.serialized_name, [])
            parent.add_child(element)
          elsif render_nil == :as_blank
            element = Lutaml::KeyValue::DataModel::Element.new(rule.serialized_name, [""])
            parent.add_child(element)
          elsif render_nil?(rule) || converted_from_empty_to_nil
            element = Lutaml::KeyValue::DataModel::Element.new(rule.serialized_name, nil)
            parent.add_child(element)
          end
          # else: Skip nil collection (default behavior)
        end

        # Handle root_mappings pattern - merge items directly into parent.
        def handle_root_mappings(parent, items, rule, root_mappings, options)
          key_attribute = root_mappings.key(:key)
          value_attribute = root_mappings.key(:value)

          parent.value ||= {} if parent.value.nil?

          if key_attribute && value_attribute
            handle_root_mappings_key_value(parent, items, key_attribute,
                                           value_attribute, rule, options)
          elsif key_attribute
            handle_root_mappings_key_only(parent, items, key_attribute,
                                          root_mappings, options)
          end
        end

        # Handle root_mappings with both key and value attributes.
        def handle_root_mappings_key_value(parent, items, key_attribute,
                                           value_attribute, rule, options)
          items.each do |item|
            next if item.nil?

            key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil
            next if key_value.nil?

            attr_value = item.respond_to?(value_attribute) ? item.public_send(value_attribute) : nil
            next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

            # Get the attribute definition for the value attribute
            item_class = item.class
            attr_def = if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
                         item_class.attributes(register_id)&.[](value_attribute)
                       end

            # Check if the value attribute has child_mappings (keyed collection)
            child_mappings = nil
            if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
              item_mapping = item_class.mappings_for(format, register_id)
              if item_mapping
                item_mapping.mappings.each do |mapping_rule|
                  if mapping_rule.to == value_attribute
                    child_mappings = mapping_rule.child_mappings if mapping_rule.respond_to?(:child_mappings)
                    break
                  end
                end
              end
            end

            serialized_value = if child_mappings
                                 # Serialize as keyed collection
                                 serialize_keyed_value_collection(attr_value, child_mappings, options)
                               elsif attr_def
                                 serialize_item_value(attr_value, attr_def, options)
                               else
                                 attr_value
                               end
            parent.value[key_value.to_s] = serialized_value if serialized_value
          end
        end

        # Serialize a collection with child_mappings as a keyed hash.
        def serialize_keyed_value_collection(collection, child_mappings, options)
          return {} if collection.nil?

          items = Array(collection)
          return {} if items.empty?

          key_attribute = keyed_collection_key_attribute(child_mappings)
          return items unless key_attribute # Fall back to array if no key mapping

          keyed_hash = {}
          items.each do |item|
            key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil
            next if key_value.nil?

            item_hash = {}
            item_class = item.class

            if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
              item_class.attributes(register_id).each do |attr_name, attr_def|
                next if attr_name == key_attribute
                next if child_mappings&.key?(attr_name) && child_mappings[attr_name] == :key

                attr_val = item.public_send(attr_name)
                next if attr_val.nil? || Lutaml::Model::Utils.uninitialized?(attr_val)

                # Use child_mappings to determine serialized name if present
                if child_mappings&.key?(attr_name)
                  mapping_value = child_mappings[attr_name]
                  serialized_name = mapping_value.is_a?(Symbol) ? mapping_value.to_s : attr_name.to_s
                else
                  serialized_name = attr_name.to_s
                end

                serialized_val = serialize_item_value(attr_val, attr_def, options)
                item_hash[serialized_name] = serialized_val unless serialized_val.nil?
              end
            end

            keyed_hash[key_value.to_s] = item_hash unless item_hash.empty?
          end

          keyed_hash
        end

        # Serialize a root mapping value.
        def serialize_root_mapping_value(attr_value, item, rule, options)
          item_class = item.class
          if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
            attr_def = item_class.attributes(register_id)&.[](rule.attribute_name)
            if attr_def
              return serialize_item_value(attr_value, attr_def, options)
            end
          end
          attr_value
        end

        # Handle root_mappings with only key attribute.
        def handle_root_mappings_key_only(parent, items, key_attribute,
                                          root_mappings, options)
          items.each do |item|
            next if item.nil?

            key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil
            next if key_value.nil?

            item_hash = {}
            item_class = item.class

            if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
              # Build a reverse mapping from root_mappings: attr_name => serialized_name_or_path
              # Skip :key since it's used as the hash key
              attr_to_serialized = {}
              root_mappings.each do |attr_name, mapping_value|
                next if mapping_value == :key
                attr_to_serialized[attr_name] = mapping_value
              end

              item_class.attributes(register_id).each do |attr_name, attr_def|
                next if attr_name == key_attribute

                attr_value = item.public_send(attr_name)
                next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

                serialized_value = serialize_item_value(attr_value, attr_def, options)
                next if serialized_value.nil?

                # Check root_mappings first, then fall back to mapping
                if attr_to_serialized.key?(attr_name)
                  mapping_value = attr_to_serialized[attr_name]
                  if mapping_value.is_a?(Array)
                    # Path spec like ["urn", "primary"]
                    apply_path_spec(item_hash, mapping_value, serialized_value)
                  else
                    # Simple name mapping like :type or "details"
                    item_hash[mapping_value.to_s] = serialized_value
                  end
                else
                  # Fall back to serialized name from the mapping
                  item_mapping = item_class.mappings_for(format, register_id)
                  serialized_name = find_serialized_name_for_attribute(item_mapping, attr_name) || attr_name.to_s
                  item_hash[serialized_name] = serialized_value
                end
              end
            end

            parent.value[key_value.to_s] = item_hash unless item_hash.empty?
          end
        end

        # Create a keyed collection element (map_key feature).
        def create_keyed_collection_element(parent, rule, items, key_attribute,
                                            child_mappings, options)
          keyed_hash = {}

          value_attribute = find_value_attribute(child_mappings)

          items.each do |item|
            key_value = item.respond_to?(key_attribute) ? item.public_send(key_attribute) : nil
            next if key_value.nil?

            if value_attribute
              serialize_keyed_value_item(keyed_hash, item, key_value,
                                         value_attribute, options)
            else
              serialize_keyed_hash_item(keyed_hash, item, key_value,
                                        key_attribute, child_mappings, options)
            end
          end

          element = Lutaml::KeyValue::DataModel::Element.new(rule.serialized_name, keyed_hash)
          parent.add_child(element)
        end

        # Find value attribute from child_mappings.
        def find_value_attribute(child_mappings)
          return nil unless child_mappings

          child_mappings.each do |attr_name, mapping_type|
            return attr_name if mapping_type == :value
          end
          nil
        end

        # Serialize a keyed collection item with value mapping.
        def serialize_keyed_value_item(keyed_hash, item, key_value,
                                       value_attribute, options)
          attr_value = item.respond_to?(value_attribute) ? item.public_send(value_attribute) : nil
          return if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

          item_class = item.class
          attr_def = nil
          if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
            attr_def = item_class.attributes(register_id)&.[](value_attribute)
          end

          serialized_value = if attr_def
                               serialize_item_value(attr_value, attr_def, options)
                             else
                               attr_value
                             end

          keyed_hash[key_value.to_s] = serialized_value unless serialized_value.nil?
        end

        # Serialize a keyed collection item as a hash.
        def serialize_keyed_hash_item(keyed_hash, item, key_value,
                                      key_attribute, child_mappings, options)
          item_hash = {}
          item_class = item.class

          apply_child_mappings(item_hash, item, child_mappings, options) if child_mappings

          if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
            serialize_item_attributes(item_hash, item, item_class, key_attribute,
                                      child_mappings, options)
          end

          keyed_hash[key_value.to_s] = item_hash unless item_hash.empty?
        end

        # Apply child mappings to build item hash.
        def apply_child_mappings(item_hash, item, child_mappings, options)
          item_class = item.class

          child_mappings.each do |attr_name, path_spec|
            next if path_spec == :key || path_spec == :value

            attr_value = item.respond_to?(attr_name) ? item.public_send(attr_name) : nil
            next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

            attr_def = nil
            if item_class.is_a?(Class) && item_class.include?(Lutaml::Model::Serialize)
              attr_def = item_class.attributes(register_id)&.[](attr_name)
            end

            serialized_value = if attr_def
                                 serialize_item_value(attr_value, attr_def, options)
                               else
                                 attr_value
                               end

            next if serialized_value.nil?

            if path_spec.is_a?(Array)
              apply_path_spec(item_hash, path_spec, serialized_value)
            else
              item_hash[attr_name.to_s] = serialized_value
            end
          end
        end

        # Serialize item attributes (for keyed collections).
        def serialize_item_attributes(item_hash, item, item_class, key_attribute,
                                      child_mappings, options)
          item_class.attributes(register_id).each do |attr_name, attr_def|
            next if attr_name == key_attribute
            next if child_mappings&.key?(attr_name)

            attr_value = item.public_send(attr_name)
            next if attr_value.nil? || Lutaml::Model::Utils.uninitialized?(attr_value)

            serialized_value = serialize_item_value(attr_value, attr_def, options)
            item_hash[attr_name.to_s] = serialized_value unless serialized_value.nil?
          end
        end

        # Apply path spec to build nested hash structure.
        def apply_path_spec(item_hash, path_spec, value)
          current = item_hash
          path_spec[0...-1].each do |key|
            key_str = key.to_s
            current[key_str] ||= {}
            current = current[key_str]
          end
          current[path_spec.last.to_s] = value
        end

        # Create an array collection element (default).
        def create_array_collection_element(parent, rule, items, options)
          coll_element = Lutaml::KeyValue::DataModel::Element.new(rule.serialized_name)

          if items.empty?
            coll_element.value = []
          else
            items.each do |item|
              child_value = create_value_for_item(rule, item, options)
              coll_element.add_child(child_value) unless child_value.nil?
            end
          end

          parent.add_child(coll_element)
        end

        # Create a value element for a collection item.
        def create_value_for_item(rule, item, options)
          return nil if item.nil?
          return nil if Lutaml::Model::Utils.uninitialized?(item)

          value_serializer.serialize_item(item, rule, options)
        end

        # Serialize an item value using the value_serializer or transformation.
        def serialize_item_value(value, attr_def, options)
          return nil if value.nil? || Lutaml::Model::Utils.uninitialized?(value)

          attr_type = attr_def.type(register_id)

          if attr_def.collection?
            serialize_collection_value(value, attr_type, options)
          elsif attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
            serialize_nested_model(value, attr_type, options)
          elsif attr_type.respond_to?(:new)
            serialize_primitive(value, attr_type)
          else
            value
          end
        end

        # Serialize a collection value.
        def serialize_collection_value(value, attr_type, options)
          items = Array(value)
          return [] if items.empty?

          # Handle Reference type collections - serialize each as a key
          if attr_type == Lutaml::Model::Type::Reference
            return items.map do |item|
              item.respond_to?(:"to_#{format}") ? item.send(:"to_#{format}") : item
            end
          end

          if attr_type.is_a?(Class) && attr_type < Lutaml::Model::Serialize
            items.map do |item|
              serialize_nested_model(item, attr_type, options)
            end
          else
            value
          end
        end

        # Serialize a nested model.
        def serialize_nested_model(value, attr_type, options)
          child_transformation = create_transformation(attr_type)
          child_root = child_transformation.transform(value, options)
          child_hash = child_root.to_hash
          child_hash["__root__"]
        end

        # Serialize a primitive value.
        def serialize_primitive(value, attr_type)
          wrapped_value = attr_type.new(value)
          wrapped_value.send(:"to_#{format}")
        end

        # Create a transformation for a type class.
        def create_transformation(type_class)
          transformation_factory.call(type_class)
        end

        # Find the serialized name for an attribute from the mapping.
        #
        # @param mapping [Mapping] The mapping to search
        # @param attr_name [Symbol] The attribute name
        # @return [String, nil] The serialized name or nil
        def find_serialized_name_for_attribute(mapping, attr_name)
          return nil unless mapping

          mapping.mappings.each do |rule|
            return rule.name.to_s if rule.to == attr_name
          end

          nil
        end
      end
    end
  end
end
