# frozen_string_literal: true

module Lutaml
  module Model
    class Transform
      @transform_cache = {}

      # Maximum number of cached Transform instances before eviction.
      # Covers most OOXML/ISO schemas with ~1000+ classes and multiple registers.
      MAX_CACHE_SIZE = 2048

      def self.data_to_model(context, data, format, options = {})
        register = options[:register] || Lutaml::Model::Config.default_register
        transform = cached_transform(context, register)
        transform.data_to_model(data, format, options)
      end

      def self.model_to_data(context, model, format, options = {})
        register = model.lutaml_register if model.is_a?(Lutaml::Model::Serialize)
        register ||= Lutaml::Model::Config.default_register
        transform = cached_transform(context, register)
        transform.model_to_data(model, format, options)
      end

      def self.cached_transform(context, register)
        @transform_cache ||= {}
        cache_key = [context, register]
        entry = @transform_cache[cache_key]
        return entry if entry

        evict_if_needed if @transform_cache.size >= MAX_CACHE_SIZE
        @transform_cache[cache_key] = new(context, register)
      end

      def self.clear_cache!
        @transform_cache&.clear
      end

      def self.cache_size
        @transform_cache&.size || 0
      end

      def self.invalidate_for(context, register = nil)
        return unless @transform_cache

        if register
          @transform_cache.delete([context, register])
        else
          @transform_cache.reject! { |(ctx, _reg)| ctx == context }
        end
      end

      def self.evict_if_needed
        # Evict oldest half of entries when cache is full
        keys_to_remove = @transform_cache.keys.first(@transform_cache.size / 2)
        keys_to_remove.each { |k| @transform_cache.delete(k) }
      end
      private_class_method :evict_if_needed

      attr_reader :context, :lutaml_register

      def initialize(context, register = nil)
        @context = context
        @lutaml_register = register || Lutaml::Model::Config.default_register
      end

      def attributes
        context.attributes(lutaml_register)
      end

      def model_class
        @context.model
      end

      def data_to_model(data, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement `data_to_model`."
      end

      def model_to_data(model, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement `model_to_data`."
      end

      protected

      def apply_value_map(value, value_map, attr)
        return attr.apply_value_map(value, value_map) if attr

        # Attribute-less dispatch for custom-method-only rules.
        # Only the :nil symbolic option resolves without attribute info;
        # :empty would need an Attribute (was a crash case pre-consolidation).
        return nil if value.nil? && value_map[:nil] == :nil
        return nil if Utils.uninitialized?(value) && value_map[:omitted] == :nil

        value
      end

      def mappings_for(format, register = nil)
        context.mappings_for(format, register)
      end

      def defined_mappings_for(format)
        context.mappings[format]
      end

      def valid_rule?(rule, attribute)
        attribute || rule.custom_methods[:from]
      end

      def attribute_for_rule(rule)
        return attributes[rule.to] unless rule.delegate

        attributes[rule.delegate].type(lutaml_register).attributes[rule.to]
      end

      def register_accessor_methods_for(object, register)
        klass = object.class
        Utils.add_method_if_not_defined(klass, :lutaml_register) do
          @lutaml_register
        end
        Utils.add_method_if_not_defined(klass, :lutaml_register=) do |value|
          @lutaml_register = value
        end
        object.lutaml_register = register
      end

      def root_and_parent_assignment(instance, options)
        root_and_parent_accessor_methods_for(instance)
        return unless options.key?(:lutaml_parent) && options.key?(:lutaml_root)

        instance.lutaml_root = options[:lutaml_root] || options[:lutaml_parent]
        instance.lutaml_parent = options[:lutaml_parent]
      end

      def root_and_parent_accessor_methods_for(instance)
        Utils.add_accessor_if_not_defined(instance.class, :lutaml_parent)
        Utils.add_accessor_if_not_defined(instance.class, :lutaml_root)
      end
    end
  end
end
