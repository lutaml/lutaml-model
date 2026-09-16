# frozen_string_literal: true

module Lutaml
  module Xml
    # Hydrates model instances from a Descriptor#walk PlanValue tree,
    # keyed by each value's producing row name (never position — rows
    # for missing elements are simply absent). Native rows build
    # constructor kwargs; deferred rows (custom methods, polymorphism,
    # unions) capture their subtree verbatim and interpret it
    # post-walk — the fragment parse runs the existing interpretive
    # machinery on just that island. Delegate rules hydrate
    # post-instance onto their target object. Collection rows route
    # natively when a single one exists, else through callback rows
    # (their values echo name and type_tag; native collection values
    # echo neither — leptris-ruby#220).
    module PlanHydrator
      class << self
        # plan: the compiler's entry for model_class
        # value: the walk root PlanValue (element)
        def call(model_class, plan, value, parent: nil)
          attr_kwargs = attributes_kwargs(plan, value)
          child_kwargs, children, delegates =
            children_kwargs(model_class, plan, value)
          instance = model_class.new(**attr_kwargs, **child_kwargs)
          instance.lutaml_parent = parent if parent
          instance.lutaml_root ||= parent&.lutaml_root || parent
          children.each do |child|
            child.lutaml_parent = instance
            child.lutaml_root ||= instance.lutaml_root || instance
          end
          interpret_deferred(model_class, plan, value, instance)
          route_delegates(delegates, instance)
          instance
        end

        private

        def register
          Lutaml::Model::Config.default_register
        end

        def attributes_kwargs(plan, value)
          kwargs = {}
          plan[:attr_rows].each do |rule, attr|
            v = value.attribute(rule.name.to_s)
            next if v.nil?

            v = v.split(rule.delimiter) if rule.delimiter
            if rule.as_list && rule.as_list[:import]
              v = rule.as_list[:import].call(v)
            end
            kwargs[attr.name.to_sym] = v
          end
          kwargs
        end

        # Returns [kwargs, hydrated_child_instances, delegate_values]
        # — child instances come back so the caller can decorate
        # parent/root links once the parent exists; delegate values
        # wait for the instance (their target object must exist).
        def children_kwargs(_model_class, plan, value)
          grouped = group_children(value)
          kwargs = {}
          children = []
          delegates = []
          spellings = Hash.new { |h, k| h[k] = [] }
          plan[:rows].each do |rule, attr, kind, spelling, delegate|
            case kind
            when :scalar
              v = grouped.dig(rule.name.to_s, 0)&.string_value
              unless v.nil?
                assign(kwargs, delegates, delegate, rule, attr,
                       apply_transforms(rule, attr, v))
              end
            when :raw, :custom_method, :polymorphic, :content_deferred
              # interpreted post-instance (interpret_deferred)
            when :content
              assign(kwargs, delegates, delegate, rule, attr,
                     content_runs(value))
            when :collection_cb
              values = grouped[rule.name.to_s].to_a.map do |v|
                apply_transforms(rule, attr, v.string_value)
              end
              unless values.empty?
                assign(kwargs, delegates, delegate, rule, attr, values)
              end
            when :collection_native
              values = native_collection(value, rule.name.to_s)
              unless values.nil?
                assign(kwargs, delegates, delegate, rule, attr, values)
              end
            when :spelling
              spellings[[rule, attr]] << grouped[spelling.to_s].to_a
            when :nested
              child_plan = PlanCompiler.compile(attr.type(register),
                                                register)
              items = grouped.fetch(rule.name.to_s, []).map do |v|
                call(attr.type(register), child_plan, v)
              end
              next if items.empty?

              children.concat(items)
              assign(kwargs, delegates, delegate, rule, attr,
                     attr.collection? ? items : items.first)
            end
          end
          unless spellings.empty?
            spellings.each do |(rule, attr), groups|
              # Interpretive order for shared-attribute groups is
              # spelling-group order (first spelling's matches, then
              # the next's), not interleaved document order.
              values = groups.compact.flatten
                .map { |v| apply_transforms(rule, attr, v.string_value) }
              next if values.empty?

              delegate = delegate_of(plan, rule)
              assign(kwargs, delegates, delegate, rule, attr,
                     attr.collection? ? values : values.first)
            end
          end
          [kwargs, children, delegates]
        end

        # Deferred islands: raw subtrees become wrapper elements via a
        # fragment parse, then the interpretive machinery runs on just
        # that island — custom method invocation with an
        # element-shaped argument, or the polymorphic/union cast.
        def interpret_deferred(model_class, plan, value, instance)
          plan[:rows].each do |rule, attr, kind, _spelling, _delegate|
            case kind
            when :content_deferred
              instance.public_send(:"#{attr.name}=", content_runs(value))
            when :raw
              raws = raw_strings(value, rule)
              next if raws.empty?

              instance.public_send(:"#{attr.name}=",
                                   attr.collection? ? raws : raws.first)
            when :custom_method
              elements = raw_strings(value, rule)
                .map { |r| fragment_element(r) }
              next if elements.empty?

              args = attr.collection? ? elements : elements.first
              rule.deserialize(instance, args,
                               model_class.attributes(register),
                               model_class)
            when :polymorphic
              results = raw_strings(value, rule).map do |raw|
                attr.cast(fragment_element(raw), :xml, register,
                          polymorphic: rule.polymorphic,
                          lutaml_parent: instance,
                          lutaml_root: instance.lutaml_root || instance)
              end
              next if results.empty?

              instance.public_send(:"#{attr.name}=",
                                   attr.collection? ? results : results.first)
            end
          end
        end

        def route_delegates(delegates, instance)
          delegates.each do |rule, delegate_attr, attr, v|
            target = instance.public_send(rule.delegate)
            unless target
              # the interpretive path instantiates absent delegate
              # targets; mirror it
              target = delegate_attr.type(register).new
              instance.public_send(:"#{rule.delegate}=", target)
            end
            target.public_send(:"#{attr.name}=", v)
          end
        end

        def delegate_of(plan, rule)
          entry = plan[:rows].find { |r, _, _k, _| r.equal?(rule) }
          entry && entry[4]
        end

        # Delegate rules hold their values for post-instance routing
        # (the target object must exist first); plain rules land in
        # kwargs directly.
        def assign(kwargs, delegates, delegate, rule, attr, value)
          if delegate
            delegates << [rule, delegate, attr, value]
          else
            kwargs[attr.name.to_sym] = value
          end
        end

        def content_runs(value)
          out = []
          value.count.times do |i|
            c = value.at(i)
            next unless c.name.nil? && c.kind == :collection

            out.concat(Array.new(c.count) { |j| c.at(j).string_value })
          end
          out
        end

        # Native collection rows echo their producing row's name
        # (leptris 1.9.178).
        def native_collection(value, name)
          value.count.times do |i|
            c = value.at(i)
            next unless c.kind == :collection && c.name == name

            return Array.new(c.count) { |j| c.at(j).string_value }
          end
          nil
        end

        def raw_strings(value, rule)
          out = []
          value.count.times do |idx|
            child = value.at(idx)
            if child.name == rule.name.to_s && child.kind == :raw
              out << child.string_value
            end
          end
          out
        end

        # Fragment deferral: parse the captured subtree back into a
        # wrapper element. Ancestor namespace context is absent (the
        # compiler only defers on namespace-free model chains).
        def fragment_element(raw)
          Lutaml::Xml::Adapter::LeptrisAdapter.parse(raw).root
        end

        def apply_transforms(rule, attr, value)
          return value unless rule.transform.is_a?(Class)

          rule.transform_value(attr, value, :from, :xml)
        end

        def group_children(value)
          grouped = {}
          value.count.times do |i|
            child = value.at(i)
            next if child.name.nil? # content runs, read separately

            (grouped[child.name] ||= []) << child
          end
          grouped
        end
      end
    end
  end
end
