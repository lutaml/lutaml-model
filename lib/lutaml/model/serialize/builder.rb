# frozen_string_literal: true

module Lutaml
  module Model
    module Serialize
      # Builder interface for constructing model instances with mixed content.
      #
      # Provides two syntaxes:
      #
      # == NO MAGIC (Explicit Receiver)
      #
      #   group = Group.new do |g|
      #     g.member(person1)
      #     g.member_key("john")
      #     g.description "\n  He is a good man.\n"
      #   end
      #
      # == MAGIC (instance_eval — No Receiver)
      #
      #   group = Group.new do
      #     member(person1)
      #     member_key("john")
      #     description "\n  He is a good man.\n"
      #   end
      #
      # Both syntaxes track the order of calls for mixed_content serialization.
      module Builder
        # Override initialize to support builder block syntax.
        #
        # When a block is passed, evaluates it in the model's context.
        # For mixed_content models, tracks call order in element_order.
        #
        # @param attrs [Hash] Attribute values (ignored when block given)
        # @param options [Hash] Options (ignored when block given)
        # @param block [Proc, nil] Optional builder block
        def initialize(attrs = {}, options = {}, &block)
          # Call parent initialize
          super(attrs, options)

          return self unless block

          # Enable order tracking for mixed_content models
          @__order_tracking__ = mixed_content?

          # Evaluate the block - use instance_eval for no-receiver style
          # The block's first parameter determines the style:
          # - |g| -> explicit receiver (block.call(g))
          # - no param -> instance_eval (&block)
          if block.arity.zero?
            instance_eval(&block)
          else
            yield(self)
          end

          self
        end

        # Check if this model has mixed_content enabled
        # @return [Boolean]
        def mixed_content?
          mapping = self.class.mappings_for(:xml, lutaml_register)
          mapping&.mixed_content? || false
        end

        private

        # Intercept method calls to track order for mixed_content
        def method_missing(method_name, *args, &block)
          # Check if this is an attribute setter call
          setter_name = :"#{method_name}="
          if args.length == 1 && attribute_exist?(setter_name)
            # Track order before calling the actual setter
            track_order(method_name, args.first, block) if @__order_tracking__

            # Call the actual setter
            send(setter_name, args.first)
          elsif args.empty? && block
            # Block form: attribute { |nested| nested.attr value }
            # This handles nested model construction
            handle_nested_block(method_name, block)
          else
            super
          end
        end

        # Respond to attribute setters
        def respond_to_missing?(method_name, include_private = false)
          setter_name = :"#{method_name}="
          attribute_exist?(setter_name) || super
        end

        # Track a setter call for mixed_content order
        #
        # @param method_name [Symbol] The attribute name (without =)
        # @param value [Object] The value being set
        # @param block [Proc, nil] Optional block for nested construction
        def track_order(method_name, value, block)
          @element_order ||= []
          @element_order << build_order_entry(method_name, value, block)
        end

        # Build an element order entry for tracking
        #
        # @param method_name [Symbol] The attribute name
        # @param value [Object] The value
        # @param block [Proc, nil] Optional block
        # @return [Lutaml::Xml::Element] The order entry
        def build_order_entry(method_name, value, _block)
          # Get the XML element name and mapping from mapping
          xml_mapping = self.class.mappings_for(:xml, lutaml_register)
          element_mapping = xml_mapping&.find_element(method_name)
          content_mapping = xml_mapping&.content_mapping

          # Check if this attribute is mapped as content (text)
          is_content_attribute = content_mapping&.to == method_name

          if is_content_attribute
            # Text content node
            Lutaml::Xml::Element.new(
              "Text",
              "text",
              node_type: :text,
              text_content: value.to_s,
            )
          else
            # Element node
            element_name = element_mapping&.name || method_name.to_s
            Lutaml::Xml::Element.new(
              "Element",
              element_name,
              node_type: :element,
              namespace_uri: nil,
              namespace_prefix: nil,
            )
          end
        end

        # Handle nested block construction: attribute { |nested| nested.attr value }
        #
        # @param method_name [Symbol] The attribute name
        # @param block [Proc] The block for nested construction
        def handle_nested_block(method_name, block)
          # Get the attribute's class
          attr_def = self.class.attributes[lutaml_register][method_name]
          return super unless attr_def

          klass = attr_def.type(lutaml_register)
          return super unless klass < Lutaml::Model::Serializable

          # Create nested instance
          nested = klass.new

          # Evaluate block in nested's context
          if block.arity.zero?
            nested.instance_eval(&block)
          else
            block.call(nested)
          end

          # Track order
          track_order(method_name, nested, block) if @__order_tracking__

          # Add to collection
          send(method_name, nested)
        end
      end
    end
  end
end
