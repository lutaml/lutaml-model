# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Aligns a model's element_order with the values it currently holds.
      #
      # element_order describes the source document, not the model. Anything
      # assigned after parsing has no entry in it, so OrderedApplier would
      # never emit that value. Reconciliation inserts the missing entries
      # before serialization starts.
      #
      # Only insertion is needed. A collection that shrank already emits the
      # right count, because process_collection_item stops yielding once the
      # index passes the value length.
      #
      # The model's own element_order is never modified: the reconciled array
      # is a local view, so repeated to_xml calls stay idempotent.
      module OrderReconciler
        # @param model_instance [Object] The model instance
        # @param compiled_rules [Array<CompiledRule>] The compiled rules
        # @param options [Hash] Transformation options
        # @return [Array(Array, Array<CompiledRule>)] the element order with
        #   any missing entries inserted, and the rules it could not
        #   reconcile that still hold an unemitted value. The caller must
        #   emit those the ordinary way or their value is lost. When nothing
        #   is missing the model's own order comes back untouched.
        def reconciled_element_order(model_instance, compiled_rules, options)
          order = model_instance.element_order
          element_rules = element_typed_rules(compiled_rules)

          # Resolve every entry to its rule once. Coverage, insertion
          # anchors and the final array all read from this, so no later
          # step rescans the order or re-matches a rule.
          resolved = order.map { |object| find_rule_for_element(object, compiled_rules) }
          coverage = ::Hash.new(0)
          resolved.each { |rule| coverage[rule] += 1 if rule }

          deficits, fallback = classify_rules(element_rules, coverage,
                                              model_instance, options)
          return [order, fallback] if deficits.empty?

          [insert_deficits(order, deficits, element_rules, resolved), fallback]
        end

        private

        def element_typed_rules(compiled_rules)
          compiled_rules.select do |rule|
            rule.is_a?(::Lutaml::Model::CompiledRule) &&
              rule.option(:mapping_type) == :element
          end
        end

        # Custom-method element rules are compiled without a backing
        # attribute, so they expose no value whose cardinality or
        # explicitness could be measured. OrderedApplier invokes them
        # directly and never reads their value either.
        def reconcilable?(rule, options)
          !attributeless_custom_rule?(rule) && valid_mapping?(rule, options)
        end

        def attributeless_custom_rule?(rule)
          rule.has_custom_methods? && rule.attribute_type.nil?
        end

        # Split the element rules that are short of entries into the ones
        # reconciliation can place and the ones it cannot.
        #
        # A rule it cannot place still holds a value nothing has emitted, so
        # it comes back as a fallback for the caller to serialize the
        # ordinary way. Dropping it would be the very data loss this file
        # exists to stop.
        #
        # A rule that is neither short nor unemitted costs only the
        # `using_default?` lookup inside expected_element_count, and the
        # ambiguity scan runs solely for the ones that are short.
        #
        # @return [Array(Hash<CompiledRule, Integer>, Array<CompiledRule>)]
        def classify_rules(element_rules, coverage, model_instance, options)
          deficits = {}
          fallback = []

          element_rules.each do |rule|
            missing = expected_element_count(rule, model_instance) -
              coverage[rule]
            next unless missing.positive?

            if reconcilable?(rule, options) &&
                unambiguous?(rule, element_rules)
              deficits[rule] = missing
            elsif coverage[rule].zero? &&
                emit_uncovered?(rule, element_rules, model_instance)
              fallback << rule
            end
          end

          [deficits, fallback]
        end

        # Whether a rule reconciliation could not place should still be
        # emitted the ordinary way.
        #
        # Yes for an unambiguous rule: nothing else will emit its value.
        #
        # For rules sharing a serialized name, it depends on where
        # element_order came from, because the dispatcher cannot tell them
        # apart. A parsed order already stands for all of them — every one
        # parsed from the same entry — so emitting the ones it did not
        # resolve to would duplicate the element on a plain round-trip. An
        # order built by a builder block records one entry per mutation, so
        # a rule with no coverage genuinely has not been emitted.
        def emit_uncovered?(rule, element_rules, model_instance)
          return true if unambiguous?(rule, element_rules)

          model_instance.respond_to?(:order_tracking_enabled?) &&
            model_instance.order_tracking_enabled?
        end

        # Entries to insert, keyed by the position in the original order
        # they go before. Built in declaration order so several rules
        # landing on one position keep their mapping order.
        def insert_deficits(order, deficits, element_rules, resolved)
          rule_index = {}
          element_rules.each_with_index { |rule, i| rule_index[rule] = i }

          insertions = deficits.each_with_object({}) do |(rule, missing), acc|
            at = insertion_index(resolved, rule, rule_index)
            entries = ::Array.new(missing) { new_order_entry(rule) }
            (acc[at] ||= []).concat(entries)
          end

          rebuild_order(order, insertions)
        end

        def rebuild_order(order, insertions)
          result = []
          order.each_with_index do |object, index|
            pending = insertions[index]
            result.concat(pending) if pending
            result << object
          end
          tail = insertions[order.length]
          result.concat(tail) if tail
          result
        end

        # How many child elements the rule's current value should produce.
        #
        # Only values the caller explicitly set are counted. A parsed model
        # keeps defaults and the uninitialized sentinel for elements absent
        # from the source document, and turning those into new elements is
        # exactly the over-emission that reverted an earlier attempt at this
        # fix.
        def expected_element_count(rule, model_instance)
          owner = value_owner(rule, model_instance)
          return 0 unless owner.respond_to?(:using_default?)
          # A custom-method rule compiled without an attribute exposes no
          # value to measure, and reading one would call a method that does
          # not exist.
          return 0 if attributeless_custom_rule?(rule)

          value = extract_ordered_rule_value(rule, model_instance)
          return 0 if unmutated_default?(owner, rule, value)
          return 0 if should_skip_delegated_value?(value, rule, owner)
          # A custom `to:` method is handed the whole model and emits every
          # value itself, and OrderedApplier calls it once per matching
          # entry. One entry means one invocation, however many values the
          # attribute holds.
          return 1 if rule.custom_methods[:to]
          return 1 unless rule.collection?

          collection_element_count(value, rule)
        end

        def collection_element_count(value, rule)
          # Mirror the applier's own dispatch. A value it will not iterate
          # — nil, or a String — never reaches process_collection_item; it
          # goes through apply_rule, which emits one element (xsi:nil under
          # render_nil).
          return 1 unless value.respond_to?(:each) && !value.is_a?(String)

          # Same length/size fallback process_collection_item uses, so the
          # two cannot disagree about how many items a collection holds.
          length = value.respond_to?(:length) ? value.length : value.size
          return length if length.positive?

          empty_collection_renders_element?(rule) ? 1 : 0
        end

        # Whether the attribute still holds its default and nothing has put
        # real data in it.
        #
        # This is the guard that keeps a parsed model from turning defaults
        # and uninitialized sentinels into elements the source document
        # never had. It follows RenderPolicy#should_skip_default? rather
        # than inventing a second rule: a collection mutated in place is
        # real data, because `items << "x"` never reaches the setter and so
        # leaves `using_default?` true.
        def unmutated_default?(owner, rule, value)
          return false unless owner.using_default?(rule.attribute_name)
          return false if rule.option(:render_default)
          return false if ::Lutaml::Model::RenderPolicy
            .derived_attribute_for?(owner, rule.attribute_name)
          return false if rule.collection? &&
            !::Lutaml::Model::Utils.empty?(value)

          true
        end

        def value_owner(rule, model_instance)
          delegate = rule.option(:delegate_from)
          return model_instance unless delegate

          model_instance.public_send(delegate)
        end

        # find_rule_for_element resolves an inserted entry back to the FIRST
        # element rule matching its name and namespace, and that match
        # accepts a nil rule namespace, namespace aliases and name aliases.
        # When more than one rule would claim the entry, reconciling would
        # feed the value to the wrong rule, so leave the rule alone.
        def unambiguous?(rule, element_rules)
          matches = element_rules.select do |candidate|
            matches_element_rule?(candidate, rule.serialized_name,
                                  rule.namespace_class&.uri)
          end

          matches == [rule]
        end

        def new_order_entry(rule)
          ::Lutaml::Xml::Element.new(
            "Element",
            rule.serialized_name,
            node_type: :element,
            namespace_uri: rule.namespace_class&.uri,
            namespace_prefix: nil,
          )
        end

        # Where a rule's new entries go:
        # - after the last entry that already resolves to it, so extra
        #   collection items follow the existing ones and any interleaved
        #   element keeps its place
        # - otherwise at the first entry declared after it, so a newly-set
        #   element lands in mapping-declaration order
        def insertion_index(resolved, rule, rule_index)
          own = rule_index[rule]
          last_own = nil
          first_later = nil

          resolved.each_with_index do |matched, index|
            next unless matched

            last_own = index if matched.equal?(rule)
            first_later ||= index if rule_index[matched] > own
          end

          return last_own + 1 if last_own

          first_later || resolved.length
        end
      end
    end
  end
end
