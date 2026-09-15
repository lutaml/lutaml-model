# frozen_string_literal: true

module Lutaml
  module Xml
    # Hydrates model instances from a Descriptor#walk PlanValue tree,
    # keyed by each value's producing row name (never position — rows
    # for missing elements are simply absent). Builds constructor
    # kwargs recursively and instantiates through .new, so typing,
    # defaults, and collection semantics all ride the constructor.
    module PlanHydrator
      class << self
        # plan: the compiler's entry for model_class
        # value: the walk root PlanValue (element)
        def call(model_class, plan, value)
          kwargs = attributes_kwargs(plan, value)
          kwargs.merge!(children_kwargs(model_class, plan, value))
          model_class.new(**kwargs)
        end

        private

        def attributes_kwargs(plan, value)
          kwargs = {}
          plan[:attr_rows].each do |rule, attr|
            v = value.attribute(rule.name.to_s)
            kwargs[attr.name.to_sym] = v unless v.nil?
          end
          kwargs
        end

        def children_kwargs(_model_class, plan, value)
          register = Lutaml::Model::Config.default_register
          grouped = group_children_by_name(value)

          kwargs = {}
          plan[:rows].each do |rule, attr, kind|
            values = grouped[kind == :collection ? :__collection : rule.name.to_s]
            next if values.nil? || values.empty?

            kwargs[attr.name.to_sym] =
              case kind
              when :scalar
                values.first.string_value
              when :collection
                # One collection-row value per element; its items are
                # the individual scalar matches.
                values.flat_map do |cv|
                  Array.new(cv.count) { |i| cv.at(i).string_value }
                end
              when :nested
                child_plan = PlanCompiler.compile(attr.type(register),
                                                  register)
                items = values.map do |v|
                  call(attr.type(register), child_plan, v)
                end
                attr.collection? ? items : items.first
              end
          end
          kwargs
        end

        # Scalar and nested values echo their producing row's name;
        # collection values echo neither name nor type_tag, so with the
        # compiler's single-collection-row guard they are attributed by
        # kind.
        def group_children_by_name(value)
          grouped = {}
          value.count.times do |i|
            child = value.at(i)
            key = child.name || (child.kind == :collection ? :__collection : nil)
            next if key.nil?

            (grouped[key] ||= []) << child
          end
          grouped
        end
      end
    end
  end
end
