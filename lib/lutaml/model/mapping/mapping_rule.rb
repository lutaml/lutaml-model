module Lutaml
  module Model
    class MappingRule
      attr_reader :name,
                  :to,
                  :render_nil,
                  :render_default,
                  :render_empty,
                  :treat_nil,
                  :treat_empty,
                  :treat_omitted,
                  :attribute,
                  :custom_methods,
                  :delegate,
                  :polymorphic,
                  :polymorphic_map,
                  :transform,
                  :format

      ALLOWED_OPTIONS = {
        render_nil: %i[
          omit
          as_nil
          as_blank
          as_empty
        ],
        render_empty: %i[
          omit
          as_empty
          as_blank
          as_nil
        ],
      }.freeze

      ALLOWED_OPTIONS.each do |key, values|
        attribute_name = key.to_s
        values.each do |value|
          define_method(:"#{attribute_name}_#{value}?") do
            send(attribute_name) == value
          end
        end
      end

      def initialize(
        name,
        to:,
        render_nil: false,
        render_default: false,
        render_empty: false,
        treat_nil: :nil,
        treat_empty: :empty,
        treat_omitted: :nil,
        with: {},
        attribute: false,
        delegate: nil,
        root_mappings: nil,
        polymorphic: {},
        polymorphic_map: {},
        transform: {},
        value_map: {}
      )
        @name = name
        @to = to
        @render_nil = render_nil
        @render_default = render_default
        @render_empty = render_empty
        @treat_nil = treat_nil
        @treat_empty = treat_empty
        @treat_omitted = treat_omitted
        @custom_methods = with
        @attribute = attribute
        @delegate = delegate
        @root_mappings = root_mappings
        @polymorphic = polymorphic
        @polymorphic_map = polymorphic_map
        @transform = transform

        @value_map = default_value_map
        @value_map[:from].merge!(value_map[:from] || {})
        @value_map[:to].merge!(value_map[:to] || {})
      end

      def default_value_map(options = {})
        render_nil_as = render_as(:render_nil, :omitted, options)
        render_empty_as = render_as(:render_empty, :empty, options)

        treat_nil_as = treat_as(:treat_nil, :nil, options)
        treat_empty_as = treat_as(:treat_empty, :empty, options)
        treat_omitted_as = treat_as(:treat_omitted, :nil, options)

        {
          from: { omitted: treat_omitted_as, nil: treat_nil_as, empty: treat_empty_as },
          to: { omitted: :omitted, nil: render_nil_as, empty: render_empty_as },
        }
      end

      def render_as(key, default_value, options = {})
        value = public_send(key)
        value = options[key] if value.nil?

        if value == true
          key.to_s.split("_").last.to_sym
        elsif value == false
          :omitted
        elsif value
          {
            as_empty: :empty,
            as_blank: :empty,
            as_nil: :nil,
            omit: :omitted,
          }[value]
        else
          default_value
        end
      end

      def treat_as(key, default_value, options = {})
        public_send(key) || options[key] || default_value
      end

      def value_map(key, options = {})
        @value_map[key]
      end

      alias from name
      # alias render_nil? render_nil
      # alias render_empty? render_empty
      alias render_default? render_default
      alias attribute? attribute

      def render?(value, instance = nil)
        if (!render_nil? && value.nil?) || (!render_empty? && Utils.empty?(value)) || (!render_omitted? && Utils.uninitialized?(value))
          # if value is nil and render nil is false, we will not render
          # if value is empty and render empty is false, we will not render
          # if value is uninitialized and render omitted is false, we will not render
          false
        elsif instance.respond_to?(:using_default?) && instance.using_default?(to)
          render_default?
        else
          true
        end
      end

      def render_nil?
        value_map(:to)[:nil] != :omitted
      end

      def render_empty?
        value_map(:to)[:empty] != :omitted
      end

      def render_omitted?
        value_map(:to)[:omitted] != :omitted
      end

      def treat_nil?
        value_map(:from)[:nil] != :omitted
      end

      def treat_empty?
        value_map(:from)[:empty] != :omitted
      end

      def treat_omitted?
        value_map(:from)[:omitted] != :omitted
      end

      def polymorphic_mapping?
        polymorphic_map && !polymorphic_map.empty?
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
          return if to.nil?

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
          mapper_class.new.send(custom_methods[:from], model, value) unless value.nil?
        elsif delegate
          if Utils.uninitialized?(model.public_send(delegate)) || model.public_send(delegate).nil?
            model.public_send(:"#{delegate}=", attributes[delegate].type.new)
          end

          model.public_send(delegate).public_send(:"#{to}=", value)
        elsif transform_method = transform[:import] || attributes[to].transform_import_method
          model.public_send(:"#{to}=", transform_method.call(value))
        else
          model.public_send(:"#{to}=", value)
        end
      end

      def using_custom_methods?
        !custom_methods.empty?
      end

      def multiple_mappings?
        name.is_a?(Array)
      end

      def raw_mapping?
        name == Constants::RAW_MAPPING_KEY
      end

      def eql?(other)
        other.class == self.class &&
          instance_variables.all? do |var|
            instance_variable_get(var) == other.instance_variable_get(var)
          end
      end
      alias == eql?

      def deep_dup
        raise NotImplementedError, "Subclasses must implement `deep_dup`."
      end
    end
  end
end
