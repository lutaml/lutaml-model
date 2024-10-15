module Lutaml
  module Model
    class MappingRule
      attr_reader :name,
                  :to,
                  :render_nil,
                  :custom_methods,
                  :delegate,
                  :mixed_content,
                  :child_mappings,
                  :default_namespace

      def initialize(
        name,
        to:,
        render_nil: false,
        with: {},
        delegate: nil,
        mixed_content: false,
        namespace_set: false,
        prefix_set: false,
        default_namespace: nil,
        child_mappings: nil
      )
        @name = name
        @to = to
        @render_nil = render_nil
        @custom_methods = with
        @delegate = delegate
        @mixed_content = mixed_content
        @namespace_set = namespace_set
        @prefix_set = prefix_set
        @child_mappings = child_mappings
        @default_namespace = default_namespace
      end

      alias from name
      alias render_nil? render_nil

      def prefixed_name
        if prefix
          "#{prefix}:#{name}"
        else
          name
        end
      end

      def namespaced_name
        if name == "lang"
          "#{prefix}:#{name}"
        elsif namespace || default_namespace
          "#{namespace || default_namespace}:#{name}"
        else
          name
        end
      end

      def serialize_attribute(model, element, doc)
        if custom_methods[:to]
          model.send(custom_methods[:to], model, element, doc)
        end
      end

      def to_value_for(model)
        if delegate
          model.public_send(delegate).public_send(to)
        else
          model.public_send(to)
        end
      end

      def serialize(model, parent = nil, doc = nil)
        if custom_methods[:to]
          model.send(custom_methods[:to], model, parent, doc)
        else
          to_value_for(model)
        end
      end

      def deserialize(model, value, attributes, mapper_class = nil)
        if custom_methods[:from]
          mapper_class.new.send(custom_methods[:from], model, value)
        elsif delegate
          if model.public_send(delegate).nil?
            model.public_send(:"#{delegate}=", attributes[delegate].type.new)
          end

          model.public_send(delegate).public_send(:"#{to}=", value)
        else
          model.public_send(:"#{to}=", value)
        end
      end

      def namespace_set?
        @namespace_set
      end

      def prefix_set?
        @prefix_set
      end

      def content_mapping?
        name.nil?
      end
    end
  end
end
