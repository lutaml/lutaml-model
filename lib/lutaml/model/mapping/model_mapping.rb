# frozen_string_literal: true

module Lutaml
  module Model
    class ModelMapping
      attr_reader :mappings

      def initialize(source = nil, target = nil, transformer = nil)
        @mappings = {}
        @source = source
        @target = target
        @transformer = transformer
      end

      def map(
        from: nil,
        to: nil,
        transform: nil,
        reverse_transform: nil,
        collection: false,
        &block
      )
        mapping_name = name_for_mapping(from, to)
        from_attr = @source.attributes[from.to_sym]
        to_attr = @target.attributes[to.to_sym]
        validate!(mapping_name, from_attr, to_attr)
        @mappings[mapping_name] = ModelMappingRule.new(
          from: from_attr,
          to: to_attr,
          transform: transform,
          reverse_transform: reverse_transform,
          collection: collection,
          mapping: if block
                     self.class.new(from_attr.type, to_attr.type,
                                    @transformer)
                   end,
        )
        @mappings[mapping_name].mapping.instance_eval(&block) if block
      end

      def map_each(
        from: nil,
        to: nil,
        transform: nil,
        reverse_transform: nil,
        &block
      )
        map(
          from: from,
          to: to,
          transform: transform,
          reverse_transform: reverse_transform,
          collection: true,
          &block
        )
      end

      def process_mappings(input, reverse: false)
        return input if Utils.blank?(input)

        transformed = {}
        @mappings.each_value do |rule|
          from_attr, to_attr = transform_attributes(rule, reverse: reverse)
          next if from_attr.nil? || to_attr.nil?

          value = input.send(from_attr.name)

          value = transformed_value(value, rule, from_attr, to_attr,
                                    reverse: reverse)

          transformed[to_attr.name] = value
        end

        transformed
      end

      private

      def transformed_value(value, rule, from_attr, to_attr, reverse: false)
        return value if Utils.blank?(value)

        if rule.collection
          return transform_collection(value, rule, from_attr, to_attr,
                                      reverse)
        end

        rule.transform_value(@transformer, to_attr, value, reverse: reverse)
      end

      def transform_collection(value, rule, from_attr, to_attr, reverse)
        return value if Utils.blank?(value)

        if !from_attr.options[:collection] || !to_attr.options[:collection]
          raise MappingAttributeTypeError,
                "Both 'from' and 'to' attributes must be collections for collection mapping"
        end

        if value.is_a?(Array)
          return value.map do |v|
            transformed_value(v, rule, from_attr, to_attr,
                              reverse: reverse)
          end
        end

        rule.transform_value(@transformer, to_attr, value, reverse: reverse)
      end

      def transform_attributes(rule, reverse: false)
        attrs = [rule.from, rule.to]
        reverse ? attrs.reverse : attrs
      end

      def name_for_mapping(from, to)
        "#{from}-to-#{to}"
      end

      def validate!(mapping_name, from, to)
        if from.nil? || from.name.to_s.strip.empty?
          raise MappingAttributeMissingError,
                "Mapping 'from' is required"
        end
        if to.nil? || to.name.to_s.strip.empty?
          raise MappingAttributeMissingError,
                "Mapping 'to' is required"
        end
        if @mappings.key?(mapping_name)
          raise MappingAlreadyExistsError,
                "Mapping already exists from: #{from.name} to: #{to.name}"
        end
      end
    end
  end
end
