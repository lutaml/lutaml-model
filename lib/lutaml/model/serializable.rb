# frozen_string_literal: true

module Lutaml
  module Model
    class Serializable
      # ComparableModel is included at the Serialize module level; its
      # ClassMethods (diff_with_score) must extend the class that
      # model classes actually inherit from (lutaml-model#18).
      include Serialize
      extend ComparableModel::ClassMethods

      # Ivars that must never take part in inspect output: they either
      # walk the whole graph (@lutaml_parent climbs to the root, and
      # parent-child mutual recursion never terminates under the
      # default Object#inspect) or are bulky parse bookkeeping.
      INSPECT_EXCLUDED_IVARS = %i[
        @lutaml_parent @lutaml_root @lutaml_register @using_default
        @element_order @attribute_order @encoding
      ].freeze

      # Bounded, Struct-like inspect: scalars by value, collections by
      # size, child models by class name. The default Object#inspect
      # recurses through @lutaml_parent and re-enters children forever
      # on real parsed documents.
      def inspect
        parts = (instance_variables - INSPECT_EXCLUDED_IVARS).map do |iv|
          "#{iv}=#{self.class.inspect_value(instance_variable_get(iv))}"
        end
        attrs = " #{parts.join(', ')}" unless parts.empty?
        "#<#{self.class.name}#{attrs}>"
      end

      class << self
        def inspect_value(value)
          case value
          when nil, true, false, Numeric, Symbol then value.inspect
          when String then value.inspect.length > 48 ? "#{value.inspect[0, 45]}...".inspect : value.inspect
          when Array then "(#{value.size} items)"
          when Hash then "{#{value.size} keys}"
          else "##{value.class.name}"
          end
        end
      end
    end
  end
end
