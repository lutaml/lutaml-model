# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Module for applying rules in element order for round-trip preservation.
      #
      # When element_order was captured during parsing (model was deserialized
      # from XML) AND the mapping is marked as ordered, this module ensures
      # the original XML structure is preserved during serialization.
      module OrderedApplier
        # Apply rules in the order specified by element_order
        #
        # This ensures round-trip serialization preserves the original XML structure.
        # For mixed content, text nodes from element_order are added directly to
        # preserve the original text interleaving.
        #
        # @param root [::Lutaml::Xml::DataModel::XmlElement] Root element
        # @param model_instance [Object] The model instance
        # @param options [Hash] Transformation options
        # @param compiled_rules [Array<CompiledRule>] The compiled rules
        # @param model_class [Class] The model class
        # @param register_id [Symbol, nil] The register ID
        # @yield Block to apply individual rules
        def apply_rules_in_order(root, model_instance, options, compiled_rules,
model_class, register_id)
          element_order = model_instance.element_order
          mapping = model_class.mappings_for(:xml, register_id)

          # Track index per element type for collection attributes
          element_indices = ::Hash.new(0)

          # Track text node index for content-mapped attribute access.
          text_node_index = 0

          # Track whether we processed any text nodes from element_order
          processed_text_nodes = false

          # Find the content rule to get CDATA flag for mixed content text
          content_rule = compiled_rules.find do |r|
            r.option(:mapping_type) == :content
          end
          root.cdata = true if content_rule&.cdata

          # Pre-check: can we use the content attribute for indexed text access?
          # This requires the content array length to match the text node count
          # in element_order. When they match, mutations to the content array
          # are reflected in serialization. When they don't match (e.g., CDATA
          # creates extra whitespace text nodes), we fall back to element_order.
          text_node_count = element_order.count { |o| o.type == "Text" }
          content_value = content_rule &&             model_instance&.public_send(content_rule.attribute_name)
          use_content_index = content_rule && content_value.is_a?(Array) &&
            content_value.length == text_node_count

          # Iterate through element_order to preserve original sequence
          element_order.each do |object|
            result = process_element_order_item(
              object, root, model_instance, options,
              compiled_rules, mapping, element_indices,
              content_rule, text_node_index, text_node_count,
              use_content_index
            ) do |action, rule, value, xsi_nil_flag|
              yield(action, rule, value, xsi_nil_flag) if block_given?
            end
            text_node_index += 1 if object.type == "Text"
            processed_text_nodes = true if result == :text_node
          end

          # Apply remaining rules that weren't in element_order (attributes only)
          apply_remaining_rules(root, model_instance, options, compiled_rules,
                                mapping, processed_text_nodes) do |action, rule, value|
            yield(action, rule, value) if block_given?
          end
        end

        # Apply element rule for a single value from a collection
        #
        # @param parent [::Lutaml::Xml::DataModel::XmlElement] Parent element
        # @param rule [CompiledRule] The rule
        # @param value [Object] The single value
        # @param options [Hash] Options
        # @yield Block to create element for value
        def apply_element_rule_single(parent:, rule:, value:, options:)
          # raw: :element — value is a complete XML element string, inject directly
          if rule.raw == :element
            add_raw_element_fragments(parent, value)
            return
          end

          # Extract parent's namespace info for element_form_default inheritance
          parent_ns_class = parent.namespace_class
          # Only pass element_form_default VALUE if it was explicitly set
          # When not set (defaults to :unqualified), pass nil to avoid incorrect blank namespace treatment
          parent_element_form_default = if parent_ns_class&.element_form_default_set?
                                          parent_ns_class.element_form_default
                                        end

          # Merge parent context into options
          child_options = options.merge(
            parent_namespace_class: parent_ns_class,
            parent_element_form_default: parent_element_form_default,
            parent_element: parent,
          )

          element = yield(rule, value, child_options)
          parent.add_child(element) if element
        end

        # Find the mapping rule for an element from element_order
        #
        # @param object [Xml::Element] Element from element_order
        # @param compiled_rules [Array<CompiledRule>] The compiled rules
        # @return [CompiledRule, nil] The matching rule or nil
        def find_rule_for_element(object, compiled_rules)
          return nil unless object.type == "Element"

          object_ns_uri = object.namespace_uri # nil if old element_order (backward compat)

          compiled_rules.find do |r|
            r.is_a?(::Lutaml::Model::CompiledRule) &&
              r.option(:mapping_type) == :element &&
              matches_element_rule?(r, object.name, object_ns_uri)
          end
        end

        private

        # Match by name AND namespace when object has a namespace URI.
        # Falls back to name-only match for backward compatibility.
        # Also checks uri_aliases for namespace alias support (e.g., ReqIF versions).
        #
        # @param rule [CompiledRule] The compiled rule
        # @param name [String] Element name
        # @param object_ns_uri [String, nil] Namespace URI from parsed XML
        # @return [Boolean] true if the rule matches
        def matches_element_rule?(rule, name, object_ns_uri)
          return rule.matches_name?(name) if object_ns_uri.nil?

          rule_ns_class = rule.namespace_class
          return rule.matches_name?(name) if rule_ns_class.nil?

          return rule.matches_name?(name) if rule_ns_class.uri.nil?

          rule_ns_matches = rule_ns_class.uri == object_ns_uri ||
            (rule_ns_class.respond_to?(:uri_aliases) &&
              rule_ns_class.uri_aliases&.include?(object_ns_uri))

          rule.matches_name?(name) && rule_ns_matches
        end

        def process_element_order_item(object, root, model_instance, options,
compiled_rules, _mapping, element_indices,
content_rule = nil, text_node_index = 0,
text_node_count = 0, use_content_index = false)
          # For text nodes in mixed content, add them directly to preserve interleaving
          if object.type == "Text"
            return process_text_node(object, root, content_rule,
                                     model_instance, text_node_index,
                                     text_node_count, use_content_index)
          end

          # For comment nodes, add them directly to preserve position
          if object.type == "Comment"
            root.add_child(::Lutaml::Xml::DataModel::XmlComment.new(object.text_content))
            return :comment_node
          end

          # Find the mapping rule for this element
          rule = find_rule_for_element(object, compiled_rules)
          return nil unless rule

          # Check if this rule should be applied based on only/except options
          return nil unless valid_mapping?(rule, options)

          # For custom methods, skip value extraction and go directly to apply_rule
          if rule.has_custom_methods? && rule.custom_methods[:to]
            yield(:apply_rule, rule, nil) if block_given?
            return nil
          end

          # Get the value for this element
          value = extract_ordered_rule_value(rule, model_instance)

          # For collection attributes, get the specific item at the tracked index
          if rule.collection? && value.respond_to?(:each) && !value.is_a?(String)
            process_collection_item(root, rule, value, object, element_indices,
                                    options) do |action, r, v, xsi_nil_flag|
              yield(action, r, v, xsi_nil_flag) if block_given?
            end
          elsif block_given?
            # Non-collection attribute, process normally
            yield(:apply_rule, rule, nil)
          end

          nil
        end

        # Process text node from element_order
        #
        # Uses the current content-mapped attribute value instead of the stale
        # text from element_order, so mutations are reflected in serialization.
        #
        # Three cases:
        # 1. Collection content with matching array/text-node count:
        #    Each text node maps 1:1 to an array element via text_index.
        # 2. Single-string content with exactly one text node:
        #    The full string replaces the single text node.
        # 3. Mismatch (e.g., CDATA creates extra whitespace nodes):
        #    Fall back to original element_order text to preserve round-trip.
        #
        # @param object [Object] The text node object
        # @param root [XmlElement] Root element
        # @param content_rule [CompiledRule, nil] The content mapping rule
        # @param model_instance [Object] The model instance
        # @param text_index [Integer] The index of this text node among all text nodes
        # @param text_node_count [Integer] Total text nodes in element_order
        # @param use_content_index [Boolean] Whether indexed content access is safe
        # @return [Symbol] :text_node
        def process_text_node(object, root, content_rule = nil,
                              model_instance = nil, text_index = 0,
                              text_node_count = 0, use_content_index = false)
          text_content = if content_rule && model_instance
                           current = model_instance.public_send(content_rule.attribute_name)

                           if use_content_index
                             # Collection content with matching count: indexed access
                             current[text_index].to_s
                           elsif !current.is_a?(Array) && text_node_count <= 1
                             # Single-string content with one text node: use current value
                             current.to_s
                           else
                             # Mismatch: fall back to element_order text (preserves round-trip)
                             object.text_content || object.name
                           end
                         else
                           object.text_content || object.name
                         end

          # Skip whitespace-only text nodes to avoid formatting artifacts,
          # but preserve them for mixed content (content_rule present) where
          # whitespace between elements is significant.
          is_mixed = !content_rule.nil?
          if text_content && (is_mixed || !text_content.strip.empty?)
            root.add_child(text_content)
            return :text_node
          end

          nil
        end

        # Extract value for a rule (handles delegation)
        # This is used during ordered iteration
        #
        # @param rule [CompiledRule] The rule
        # @param model_instance [Object] The model instance
        # @return [Object] The extracted value
        def extract_ordered_rule_value(rule, model_instance)
          if rule.option(:delegate_from)
            delegate_obj = model_instance.public_send(rule.option(:delegate_from))
            delegate_obj&.public_send(rule.attribute_name)
          else
            model_instance.public_send(rule.attribute_name)
          end
        end

        # Process a single item from a collection
        #
        # @param root [XmlElement] Root element
        # @param rule [CompiledRule] The rule
        # @param value [Array] The collection value
        # @param object [Object] The element order object
        # @param element_indices [Hash] Index tracker
        # @param options [Hash] Options
        def process_collection_item(_root, rule, value, object, element_indices,
_options)
          index = element_indices[object.name]
          value_length = value.respond_to?(:length) ? value.length : value.size

          if index < value_length
            single_value = value[index]
            element_indices[object.name] += 1

            # Skip individual nil items when value_map says nil is omitted
            to_map = (rule.option(:value_map) || {})[:to] || {}
            if !(single_value.nil? && to_map[:nil] == :omitted) && block_given?
              yield(:apply_single, rule, single_value)
            end
          elsif index.zero? && value_length.zero?
            # Handle empty collections with value_map
            to_map = (rule.option(:value_map) || {})[:to] || {}
            if to_map[:empty] == :nil
              yield(:apply_single, rule, nil, true) if block_given?
            elsif to_map[:empty] == :blank
              yield(:apply_single, rule, "") if block_given?
            end
            # For :empty and :omitted: skip — 0 items = 0 child elements
          end
        end

        # Apply remaining rules (attributes, content/raw, and any element
        # rules not represented in element_order).
        #
        # The element-type skip that used to live here caused silent data
        # loss whenever an element-typed attribute was missing from
        # element_order (e.g. when a direct setter forgot to call
        # track_order). After the builder-side fix all mutation paths
        # record into element_order, so this branch is a defense-in-depth
        # safety net: emit any element-typed rule whose value would
        # otherwise vanish.
        #
        # @param root [XmlElement] Root element
        # @param model_instance [Object] The model instance
        # @param options [Hash] Options
        # @param compiled_rules [Array<CompiledRule>] The compiled rules
        # @param mapping [Xml::Mapping] The mapping
        # @param processed_text_nodes [Boolean] Whether text nodes were processed
        def apply_remaining_rules(_root, model_instance, options,
compiled_rules, mapping, processed_text_nodes)
          attr_order = model_instance.respond_to?(:attribute_order) &&
            model_instance.attribute_order

          rules_to_apply = if attr_order
                             sort_rules_by_attribute_order(compiled_rules,
                                                           attr_order)
                           else
                             compiled_rules
                           end

          emitted_counts = element_order_coverage(model_instance,
                                                  compiled_rules)

          rules_to_apply.each do |rule|
            mapping_type = rule.option(:mapping_type)

            # Skip content/raw if mixed or text nodes were processed
            if %i[content raw].include?(mapping_type) &&
                (mapping&.mixed_content? || processed_text_nodes)
              next
            end

            if mapping_type == :element &&
                element_rule_already_emitted?(rule, model_instance,
                                              emitted_counts)
              next
            end

            next unless valid_mapping?(rule, options)

            yield(:apply_rule, rule, nil) if block_given?
          end
        end

        # Count, per element-typed rule, how many entries in element_order
        # already cover it. Returns a Hash keyed by CompiledRule identity.
        #
        # @param model_instance [Object] The model instance
        # @param compiled_rules [Array<CompiledRule>] The compiled rules
        # @return [Hash<CompiledRule, Integer>] Coverage counts
        def element_order_coverage(model_instance, compiled_rules)
          counts = ::Hash.new(0)
          return counts unless model_instance.respond_to?(:element_order)
          return counts unless (order = model_instance.element_order)

          element_rules = compiled_rules.select do |r|
            r.is_a?(::Lutaml::Model::CompiledRule) &&
              r.option(:mapping_type) == :element
          end

          order.each do |object|
            next unless object.type == "Element"

            object_ns_uri = object.namespace_uri
            matched = element_rules.find do |r|
              matches_element_rule?(r, object.name, object_ns_uri)
            end
            counts[matched] += 1 if matched
          end

          counts
        end

        # Whether an element-typed rule has already been fully emitted
        # via element_order (or should not be emitted at all by the safety
        # net). Returns true when:
        # - the model was not constructed via builder block
        #   (`@__order_tracking__` is nil/false): parsed models trust
        #   element_order as the complete source of truth, so the safety
        #   net must not second-guess it by emitting defaults/uninitialized
        #   values that the standard path would otherwise have skipped.
        # - the standard skip logic says the value should be skipped
        #   (handles defaults, render_nil/render_empty, value_map, etc.)
        # - or the rule was fully covered by element_order entries
        #
        # The safety net targets the bug class where a builder-block
        # construction bypassed element_order tracking (e.g. via a
        # mutation path that forgot to call record_mutation). After
        # Option A, all setter/getter paths record into element_order,
        # so this branch is defense-in-depth rather than the common
        # path.
        #
        # @param rule [CompiledRule] The element rule
        # @param model_instance [Object] The model instance
        # @param emitted_counts [Hash<CompiledRule, Integer>] Coverage map
        # @return [Boolean]
        def element_rule_already_emitted?(rule, model_instance,
emitted_counts)
          return true unless model_order_tracking_enabled?(model_instance)

          value = extract_ordered_rule_value(rule, model_instance)
          return true if should_skip_value?(value, rule, model_instance)

          emitted = emitted_counts[rule]
          if rule.collection?
            value_length = value.respond_to?(:length) ? value.length : 0
            emitted >= value_length
          else
            emitted.positive?
          end
        end

        # Whether the model was constructed via a builder block and thus
        # has order tracking enabled. Only such models are candidates for
        # the safety net; parsed models trust element_order as-is.
        def model_order_tracking_enabled?(model_instance)
          return false unless model_instance.respond_to?(:order_tracking_enabled?)

          model_instance.order_tracking_enabled?
        end

        # Sort compiled rules so attribute rules follow the captured attribute_order.
        # Non-attribute rules (content, raw) maintain their original position.
        #
        # @param rules [Array<CompiledRule>] The compiled rules
        # @param attr_order [Array<String>] Attribute names in document order
        # @return [Array<CompiledRule>] Rules sorted by attribute order
        def sort_rules_by_attribute_order(rules, attr_order)
          order_index = attr_order.each_with_index
            .with_object({}) { |(name, i), h| h[name] = i }

          local_index = attr_order.each_with_index
            .with_object({}) do |(name, i), h|
              local = name.include?(":") ? name.split(":", 2).last : name
              h[local] = i unless h.key?(local)
            end

          non_attr_rules, attr_rules = rules.partition do |r|
            r.option(:mapping_type) != :attribute
          end

          sorted_attr_rules = attr_rules.sort_by do |r|
            order_index[r.serialized_name] || local_index[r.serialized_name] ||
              Float::INFINITY
          end

          non_attr_rules + sorted_attr_rules
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
      end
    end
  end
end
