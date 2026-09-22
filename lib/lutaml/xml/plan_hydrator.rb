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
        # node: the parsed source element (leptris); ordered/mixed
        #   plans rebuild element_order from it and ordered children
        #   hydrate natively against their own nodes
        def call(model_class, plan, value, parent: nil, node: nil)
          buckets = node && plan[:needs_nodes] ? element_buckets(node) : nil
          attr_kwargs = attributes_kwargs(plan, value)
          child_kwargs, children, delegates =
            children_kwargs(model_class, plan, value, buckets)
          plan[:collection_defaults].each do |name|
            next if attr_kwargs.key?(name) || child_kwargs.key?(name)

            child_kwargs[name] = []
          end
          # TODO.max-perf/33: the bulk constructor — allocate +
          # compiled writers, from_hash semantics — measured ~30x on
          # hydration-heavy corpora versus the generic constructor.
          instance = model_class.instantiate(attr_kwargs.merge(child_kwargs),
                                             register)
          instance.lutaml_parent = parent if parent
          instance.lutaml_root ||= parent&.lutaml_root || parent
          instance.element_order = PlanOrder.build(node) if node && plan[:ordered]
          children.each do |child|
            child.lutaml_parent = instance
            child.lutaml_root ||= instance.lutaml_root || instance
          end
          interpret_deferred(model_class, plan, value, instance, node, buckets)
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
        def children_kwargs(_model_class, plan, value, buckets = nil)
          grouped, tagged = group_children(value, plan[:row_tags])
          buckets = nil unless buckets && plan[:needs_nodes]
          kwargs = {}
          children = []
          delegates = []
          spellings = Hash.new { |h, k| h[k] = [] }
          row_tags = plan[:row_tags]
          plan[:rows].each_with_index do |(rule, attr, kind, spelling, delegate), idx|
            tag = row_tags&.[](idx)
            case kind
            when :scalar
              # Raw passthrough: the model constructor is the single
              # cast authority — pre-casting here doubled every cast.
              # Class transforms still apply before assignment.
              if tag && (vals = tagged[tag]) && vals.size > 1
                # Interpretive parity: several captures into a
                # non-collection attribute arrive as the full array.
                v = vals.map(&:string_value)
              else
                first = if tag
                          tagged[tag]&.first
                        else
                          grouped.dig(rule.name.to_s, 0)
                        end
                v = first&.string_value
              end
              unless v.nil?
                v = rule.transform_value(attr, v, :from, :xml) if rule.transform.is_a?(Class)
                assign(kwargs, delegates, delegate, rule, attr, v)
              end
            when :raw, :custom_method, :polymorphic, :content_deferred
              # interpreted post-instance (interpret_deferred)
            when :content
              assign(kwargs, delegates, delegate, rule, attr,
                     content_runs(value))
            when :ordered_deferred
              # With a source node the child hydrates natively: one
              # walk against its own node + element_order from the
              # node's children. Without one (direct PlanHydrator
              # use), the subtree fragment-parses interpretively.
              if buckets
                child_type = attr.type(register)
                child_plan = PlanCompiler.compile(child_type, register)
                items = buckets.fetch(rule.name.to_s, []).map do |n|
                  call(child_type, child_plan,
                       child_plan[:descriptor].walk(n), node: n)
                end
                unless items.empty?
                  children.concat(items)
                  assign(kwargs, delegates, delegate, rule, attr,
                         attr.collection? ? items : items.first)
                end
              end
            when :collection_cb
              values = grouped[rule.name.to_s].to_a.map(&:string_value)
              if rule.transform.is_a?(Class)
                values = values.map { |v| rule.transform_value(attr, v, :from, :xml) }
              end
              unless values.empty?
                assign(kwargs, delegates, delegate, rule, attr, values)
              end
            when :collection_native
              values = if tag
                         tagged[tag].to_a.map(&:string_value)
                       else
                         native_collection(value, rule.name.to_s)
                       end
              unless values.nil?
                assign(kwargs, delegates, delegate, rule, attr, values)
              end
            when :spelling
              spellings[[rule, attr]] << grouped[spelling.to_s].to_a
            when :nested
              child_type = attr.type(register)
              child_plan = PlanCompiler.compile(child_type, register)
              cursor = if child_plan[:needs_nodes] && buckets
                         buckets.fetch(rule.name.to_s, [])
                       end
              items = grouped.fetch(rule.name.to_s, []).each_with_index
                .map do |v, i|
                  call(child_type, child_plan, v,
                       node: cursor && cursor[i])
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
              values = groups.compact.flatten.map(&:string_value)
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
        # With the source node available the island wraps the ORIGINAL
        # node (no fragment parse — the reparse dominated deferred
        # hydration). Ordered children only land here without a node.
        def interpret_deferred(model_class, plan, value, instance, node = nil,
                               buckets = nil)
          plan[:rows].each do |rule, attr, kind, _spelling, _delegate|
            case kind
            when :content_deferred
              runs = content_runs(value)
              next if runs.empty?

              # Non-collection content attrs hold the joined text
              # (the interpretive path assigns element text, the runs
              # concatenated).
              instance.public_send(:"#{attr.name}=", runs.join)
            when :raw
              raws = raw_strings(value, rule)
              next if raws.empty?

              instance.public_send(:"#{attr.name}=",
                                   attr.collection? ? raws : raws.first)
            when :custom_method
              elements = deferred_elements(value, rule, buckets)
              next if elements.empty?

              args = attr.collection? ? elements : elements.first
              rule.deserialize(instance, args,
                               model_class.attributes(register),
                               model_class)
            when :ordered_deferred
              next if node # hydrated natively in children_kwargs

              results = deferred_elements(value, rule, buckets).map do |element|
                attr.cast(element, :xml, register,
                          lutaml_parent: instance,
                          lutaml_root: instance.lutaml_root || instance)
              end
              next if results.empty?

              instance.public_send(:"#{attr.name}=",
                                   attr.collection? ? results : results.first)
            when :polymorphic
              results = deferred_elements(value, rule, buckets).map do |element|
                attr.cast(element, :xml, register,
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

        # Wrapper elements for deferred rows: the ORIGINAL source
        # nodes bridged through moxml's wrapper cache (wrapper
        # construction only, no parse), falling back to a fragment
        # parse of the captured subtree when no node is available.
        # Both lists are document-ordered for the row's name.
        def deferred_elements(value, rule, buckets)
          nodes = buckets && buckets[rule.name.to_s]
          return nodes.map { |n| bridge_element(n) } if nodes

          raw_strings(value, rule).map { |raw| fragment_element(raw) }
        end

        def bridge_element(node)
          Lutaml::Xml::LeptrisElement.new(
            Moxml::Node.wrap(node, bridge_context),
          )
        end

        def bridge_context
          @bridge_context ||= Moxml::Context.new(:leptris)
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

        def group_children(value, row_tags = nil)
          grouped = {}
          tagged = {}
          want_tags = !row_tags.nil?
          value.count.times do |i|
            child = value.at(i)
            next if child.name.nil? # content runs, read separately

            (grouped[child.name] ||= []) << child
            if want_tags && child.type_tag != 0
              (tagged[child.type_tag] ||= []) << child
            end
          end
          [grouped, tagged]
        end

        # Element children bucketed by local name, document order
        # preserved — the node-side mirror of group_children for
        # ordered-child hydration. Only built when the plan's subtree
        # needs source nodes; namespace-qualified models never get
        # here (the compiler keeps them interpretive).
        def element_buckets(node)
          buckets = {}
          node.children.each do |child|
            next unless child.is_a?(::Leptris::XML::Element)

            (buckets[child.name] ||= []) << child
          end
          buckets
        end
      end
    end
  end
end
