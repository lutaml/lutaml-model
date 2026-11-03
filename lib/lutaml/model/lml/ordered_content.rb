# frozen_string_literal: true

require_relative "rejected_error"

module Lutaml
  module Model
    module Lml
      # Per-instance document order of an `ordered` / mixed XML model as
      # portable data (lutaml-model#1033, "Format mappings and
      # per-instance order").
      #
      # The reserved instance member +__lml_content+ holds an ordered list
      # of tokens that, not grouped member traversal, control serialization
      # order:
      #
      #   {"kind" => "element", "attribute" => "em", "index" => 0}
      #   {"kind" => "text",    "attribute" => "body", "index" => 2}
      #   {"kind" => "text",    "literal" => "hello "}
      #   {"kind" => "cdata",   "literal" => "<raw>"}
      #
      # Element tokens address the +index+-th value of a mapped element
      # member (a scalar member has index 0). Mapped text tokens address
      # the +index+-th value of the map_content member. Namespace identity
      # is not repeated per token: it belongs to the addressed member's
      # mapping rule, and is restored from the descriptor on apply.
      #
      #   descriptor = OrderedContent.descriptor_for(Para, mapping: mapping)
      #   tokens     = OrderedContent.capture(descriptor, para)    # Ruby -> data
      #   OrderedContent.apply(descriptor, tokens, other_para)     # data -> Ruby
      #
      # Comments and processing instructions in element_order have no
      # token and are refused (+invalid_ordered_content+) rather than
      # dropped. Elements in element_order that no rule maps are not model
      # data (Ruby serialization omits them too) and are skipped.
      module OrderedContent
        MEMBER = "__lml_content"
        VERSION = 1
        KINDS = %w[element text cdata].freeze
        TOKEN_KEYS = %w[kind attribute index literal].freeze
        NATIVE_ORDER_OWNERS = %w[
          Lutaml::Xml::Serialization::InstanceMethods
          Lutaml::Xml::XmlOrderable
        ].freeze
        CDATA_NAME = "#cdata-section"
        TEXT_NAME = "text"

        # One element member: the rules (aliases) mapping it, and the
        # namespace its elements carry.
        ElementMember = Struct.new(:attribute, :names, :namespace_uri,
                                   :prefix, :collection, :discriminator,
                                   keyword_init: true) do
          def collection?
            collection
          end
        end

        # The content (map_content) member, if any.
        ContentMember = Struct.new(:attribute, :collection, :cdata,
                                   keyword_init: true) do
          def collection?
            collection
          end
        end

        # Immutable description of how one class/mapping maps to tokens.
        class Descriptor
          attr_reader :klass, :member, :elements, :content, :element_attributes

          def initialize(klass:, mixed:, elements:, content:)
            @klass = klass
            @member = MEMBER
            @mixed = mixed
            @elements = elements.freeze
            @content = content&.freeze
            @element_attributes = elements.map(&:attribute).uniq.freeze
            freeze
          end

          def mixed?
            @mixed
          end
        end

        class << self
          # Build the descriptor for +klass+'s XML +mapping+, or nil when
          # the mapping carries no per-instance order (neither `ordered`
          # nor mixed content). Raises RejectedError for imperative order
          # generation (+imperative_element_order+) and for a source
          # member that collides with the reserved name (+reserved_member+).
          def descriptor_for(klass, mapping:, register: nil)
            return nil unless mapping.ordered? || mapping.mixed_content?

            reject_reserved_member!(klass, mapping)
            reject_imperative_order!(klass, mapping)

            rules = mapping.mappings.reject(&:attribute?)
            content_rule = rules.find { |rule| rule.name.nil? }
            elements = element_members(klass, mapping, rules, register)

            Descriptor.new(
              klass: klass,
              mixed: mapping.mixed_content? || false,
              elements: elements,
              content: content_member(klass, content_rule),
            )
          end

          # Ruby element_order -> token list. Returns nil when the
          # instance carries no element_order (it will serialize in
          # mapping order), so "absent" stays distinct from "empty".
          def capture(descriptor, instance)
            order = instance.element_order
            return nil if order.nil?

            state = CaptureState.new(descriptor, instance)
            order.each { |entry| state.visit(entry) }
            state.finish
          end

          # Check +tokens+ against +descriptor+, and against +instance+'s
          # member values when given. Raises +invalid_ordered_content+.
          # Returns the normalized (string-keyed, frozen) token list.
          def validate!(descriptor, tokens, instance: nil)
            unless tokens.is_a?(Array)
              fail_invalid!(descriptor, "", "#{MEMBER} must be an array")
            end

            seen = {}
            normalized = tokens.each_with_index.map do |token, position|
              normalize_token(descriptor, token, "/#{position}").tap do |tok|
                check_reference(descriptor, tok, "/#{position}", seen, instance)
              end
            end
            normalized.freeze
          end

          # Token list -> Lutaml::Xml::Element order entries, assigned to
          # +instance.element_order+ (and returned). A nil +tokens+ leaves
          # the instance without a recorded order.
          def apply(descriptor, tokens, instance)
            if tokens.nil?
              instance.element_order = nil
              return nil
            end

            normalized = validate!(descriptor, tokens, instance: instance)
            require_ascending!(descriptor, normalized)
            require_serializable_text!(descriptor, normalized, instance)
            instance.element_order = normalized.map do |token|
              build_entry(descriptor, token, instance)
            end
          end

          def fail!(reason, klass, detail)
            raise RejectedError.new(reason, klass, detail)
          end

          def fail_invalid!(descriptor, pointer, detail)
            fail!(:invalid_ordered_content, descriptor.klass,
                  "#{MEMBER}#{pointer}: #{detail}")
          end

          private

          # Ruby serialization consumes each member's values in value
          # order, so references to one member must ascend; capture always
          # produces that. A permutation would need the member values
          # reordered, which apply never does behind the caller's back.
          def require_ascending!(descriptor, tokens)
            last = {}
            tokens.each_with_index do |token, position|
              next unless token.key?("attribute")

              key = [token["kind"] == "element", token["attribute"]]
              if last.key?(key) && token["index"] < last[key]
                fail_invalid!(descriptor, "/#{position}",
                              "#{token['attribute']}[#{token['index']}] follows a later index; " \
                              "references to one member must ascend")
              end
              last[key] = token["index"]
            end
          end

          # When the number of text and CDATA entries equals the number of
          # content values, Ruby serialization replaces entry i with value
          # i, so a literal there is silently overridden (OrderedApplier
          # #process_text_node). Otherwise each entry keeps its own text.
          # Refuse tokens that would be overridden rather than diverge;
          # capture always emits references in the matching case.
          def require_serializable_text!(descriptor, tokens, instance)
            content = descriptor.content
            return unless content

            texts = tokens.each_with_index.reject { |tok, _| tok["kind"] == "element" }
            return unless texts.size == member_values(instance, content.attribute).size

            texts.each do |token, position|
              next if token.key?("attribute")

              fail_invalid!(descriptor, "/#{position}",
                            "literal #{token['kind']} token would be overridden: the order has " \
                            "#{texts.size} text entries for #{texts.size} content values, so " \
                            "serialization substitutes each value; reference #{content.attribute}[i] instead")
            end
          end

          def reject_reserved_member!(klass, mapping)
            collides = klass.attributes.key?(MEMBER.to_sym) ||
              mapping.mappings.any? do |rule|
                rule.to.to_s == MEMBER || Array(rule.name).map(&:to_s).include?(MEMBER)
              end
            return unless collides

            fail!(:reserved_member, klass,
                  "#{MEMBER} is reserved for ordered content")
          end

          # An order-generating callback is Ruby code deciding which
          # elements come out and where. Rules with a custom +with:+
          # method on an element or content member, and a class that
          # redefines element_order itself, cannot be expressed as tokens.
          def reject_imperative_order!(klass, mapping)
            mapping.mappings.each do |rule|
              next if rule.attribute?
              next if rule.custom_methods.nil? || rule.custom_methods.empty?

              fail!(:imperative_element_order, klass,
                    "#{rule.name.inspect} maps through custom methods " \
                    "#{rule.custom_methods.keys.inspect}")
            end

            %i[element_order element_order=].each do |name|
              next unless klass.method_defined?(name)

              owner = klass.instance_method(name).owner
              next if native_order_owner?(owner)

              fail!(:imperative_element_order, klass,
                    "#{name} is overridden by #{owner}")
            end
          end

          def native_order_owner?(owner)
            NATIVE_ORDER_OWNERS.include?(owner.name)
          end

          def element_members(klass, mapping, rules, register)
            rules.reject { |rule| rule.name.nil? }
              .group_by { |rule| rule.to.to_s }
              .flat_map do |attribute, group|
                group.map do |rule|
                  build_element_member(klass, mapping, rule, attribute, register)
                end
              end
          end

          def build_element_member(klass, mapping, rule, attribute, register)
            attr = klass.attributes[rule.to]
            if attr.nil?
              fail!(:invalid_ordered_content, klass,
                    "rule #{rule.name.inspect} maps unknown attribute #{attribute}")
            end

            ns = element_namespace(klass, mapping, rule, attr, register)
            ElementMember.new(
              attribute: attribute,
              names: Array(rule.name).map(&:to_s).freeze,
              namespace_uri: ns[:uri],
              prefix: ns[:prefix],
              collection: attr.collection? || false,
              discriminator: rule.when_attribute.empty? ? nil : rule.when_attribute,
            ).freeze
          end

          # The namespace a rule's elements carry. A model-typed member
          # takes its element namespace from the child model's own mapping
          # when the rule declares none.
          def element_namespace(_klass, mapping, rule, attr, register)
            ns = rule.resolve_namespace(
              attr: attr, register: register,
              parent_ns_uri: mapping.namespace_uri,
              parent_ns_class: mapping.namespace_class,
              form_default: mapping.namespace_class&.element_form_default || :unqualified,
              parent_prefix: mapping.namespace_prefix
            )
            return ns if ns[:uri] || rule.namespace_set?

            child = attr.type(register || :default)
            return ns unless child.is_a?(::Class) && child <= ::Lutaml::Model::Serialize

            child_mapping = child.mappings_for(:xml, register)
            { uri: child_mapping.namespace_uri, prefix: child_mapping.namespace_prefix }
          end

          def content_member(klass, rule)
            return nil unless rule

            attr = klass.attributes[rule.to]
            return nil unless attr

            ContentMember.new(attribute: rule.to.to_s,
                              collection: attr.collection? || false,
                              cdata: rule.cdata ? true : false)
          end

          def normalize_token(descriptor, token, pointer)
            unless token.is_a?(::Hash)
              fail_invalid!(descriptor, pointer, "token must be an object")
            end

            tok = token.transform_keys(&:to_s)
            extra = tok.keys - TOKEN_KEYS
            unless extra.empty?
              fail_invalid!(descriptor, pointer, "unknown keys #{extra.inspect}")
            end

            kind = tok["kind"]
            unless KINDS.include?(kind)
              fail_invalid!(descriptor, pointer, "unknown kind #{kind.inspect}")
            end

            check_shape(descriptor, tok, pointer)
            tok.freeze
          end

          def check_shape(descriptor, tok, pointer)
            has_attribute = tok.key?("attribute")
            has_literal = tok.key?("literal")
            if tok["kind"] == "element"
              if has_literal || !has_attribute || !tok.key?("index")
                fail_invalid!(descriptor, pointer,
                              "element token needs attribute and index only")
              end
            elsif has_attribute == has_literal
              fail_invalid!(descriptor, pointer,
                            "#{tok['kind']} token needs exactly one of attribute+index or literal")
            end

            if has_attribute && !(tok["attribute"].is_a?(String) && valid_index?(tok["index"]))
              fail_invalid!(descriptor, pointer,
                            "attribute must be a string and index a non-negative integer")
            end
            return unless has_literal && (!tok["literal"].is_a?(String) || tok.key?("index"))

            fail_invalid!(descriptor, pointer, "literal must be a string without index")
          end

          def valid_index?(index)
            index.is_a?(Integer) && index >= 0
          end

          def check_reference(descriptor, tok, pointer, seen, instance)
            return unless tok.key?("attribute")

            attribute = tok["attribute"]
            index = tok["index"]
            if tok["kind"] == "element"
              member = descriptor.elements.find { |e| e.attribute == attribute }
              unless member
                fail_invalid!(descriptor, pointer,
                              "#{attribute} is not a mapped element member")
              end
              key = [:element, attribute, index]
              collection = member.collection?
            else
              content = descriptor.content
              unless content && content.attribute == attribute
                fail_invalid!(descriptor, pointer,
                              "#{attribute} is not the mapped content member")
              end
              key = [:content, attribute, index]
              collection = content.collection?
            end

            if seen[key]
              fail_invalid!(descriptor, pointer,
                            "duplicate reference to #{attribute}[#{index}] (first at #{seen[key]})")
            end
            seen[key] = pointer

            if !collection && index != 0
              fail_invalid!(descriptor, pointer,
                            "scalar member #{attribute} only has index 0")
            end
            check_index_exists(descriptor, attribute, index, pointer, instance) if instance
          end

          def check_index_exists(descriptor, attribute, index, pointer, instance)
            values = member_values(instance, attribute)
            return if index < values.size

            fail_invalid!(descriptor, pointer,
                          "#{attribute}[#{index}] does not exist (#{values.size} value(s))")
          end

          def member_values(instance, attribute)
            value = instance.public_send(attribute)
            case value
            when nil then []
            when ::Array then value
            else [value]
            end
          end

          def build_entry(descriptor, token, instance)
            case token["kind"]
            when "element" then element_entry(descriptor, token)
            when "text" then text_entry(descriptor, token, instance, cdata: false)
            else text_entry(descriptor, token, instance, cdata: true)
            end
          end

          def element_entry(descriptor, token)
            member = descriptor.elements.find { |e| e.attribute == token["attribute"] }
            ::Lutaml::Xml::Element.new(
              "Element", member.names.first,
              node_type: :element,
              namespace_uri: member.namespace_uri,
              namespace_prefix: member.prefix
            )
          end

          def text_entry(_descriptor, token, instance, cdata:)
            text = if token.key?("literal")
                     token["literal"]
                   else
                     member_values(instance, token["attribute"])[token["index"]].to_s
                   end
            ::Lutaml::Xml::Element.new(
              "Text", cdata ? CDATA_NAME : TEXT_NAME,
              text_content: text, node_type: cdata ? :cdata : :text
            )
          end
        end

        # Walks one instance's element_order once, producing tokens.
        class CaptureState
          def initialize(descriptor, instance)
            @descriptor = descriptor
            @instance = instance
            @tokens = []
            @next_index = ::Hash.new(0)
            @text_index = 0
            @content_values = content_values
            @text_nodes = instance.element_order.count do |e|
              e.respond_to?(:node_type) && e.node_type == :text
            end
          end

          def visit(entry)
            unless entry.respond_to?(:node_type)
              OrderedContent.fail!(:invalid_ordered_content, @descriptor.klass,
                                   "#{MEMBER}: element_order entry #{entry.inspect} is not an order entry")
            end

            case entry.node_type
            when :element then visit_element(entry)
            when :text then visit_text(entry)
            when :cdata then add("kind" => "cdata", "literal" => entry.text_content.to_s)
            else
              OrderedContent.fail!(:invalid_ordered_content, @descriptor.klass,
                                   "#{MEMBER}: #{entry.node_type} nodes have no token")
            end
          end

          # Tokens for members element_order never mentioned (added after
          # parsing) follow in declaration order, as Ruby serialization
          # appends them; a count above the member's size is stale.
          def finish
            @descriptor.element_attributes.each do |attribute|
              size = values_for(attribute).size
              used = @next_index[[:element, attribute]]
              if used > size
                OrderedContent.fail!(:invalid_ordered_content, @descriptor.klass,
                                     "#{MEMBER}: element_order lists #{used} #{attribute} " \
                                     "element(s) but the member has #{size}")
              end
              (used...size).each do |i|
                add("kind" => "element", "attribute" => attribute, "index" => i)
              end
            end
            finish_content
            @tokens.freeze
          end

          private

          def finish_content
            content = @descriptor.content
            return unless content

            (@text_index...@content_values.size).each do |i|
              add("kind" => "text", "attribute" => content.attribute, "index" => i)
            end
          end

          def add(token)
            @tokens << token.freeze
          end

          def values_for(attribute)
            OrderedContent.send(:member_values, @instance, attribute)
          end

          def content_values
            content = @descriptor.content
            return [] unless content

            values_for(content.attribute)
          end

          def visit_element(entry)
            member = match_member(entry)
            return unless member

            key = [:element, member.attribute]
            index = @next_index[key]
            @next_index[key] += 1
            add("kind" => "element", "attribute" => member.attribute, "index" => index)
          end

          def visit_text(entry)
            text = entry.text_content.to_s
            # Element-only (`ordered`) content: indentation between
            # elements is not content.
            return if !@descriptor.mixed? && text.strip.empty?

            index = @text_index
            @text_index += 1
            if mapped_text?(index, text)
              add("kind" => "text", "attribute" => @descriptor.content.attribute,
                  "index" => index)
            else
              add("kind" => "text", "literal" => text)
            end
          end

          # A text node maps to the content member when the member holds
          # the same string at that text position; a scalar member only
          # when the order has a single text node.
          def mapped_text?(index, text)
            content = @descriptor.content
            return false unless content
            return false if !content.collection? && (@text_nodes != 1 || index != 0)

            value = @content_values[index]
            !value.nil? && value.to_s == text
          end

          def match_member(entry)
            candidates = @descriptor.elements.select do |member|
              member.names.include?(entry.name.to_s) && namespace_match?(member, entry)
            end
            return candidates.first if candidates.size <= 1

            pick_by_discriminator(candidates, entry)
          end

          def namespace_match?(member, entry)
            entry.namespace_uri.nil? || member.namespace_uri.nil? ||
              member.namespace_uri == entry.namespace_uri
          end

          def pick_by_discriminator(candidates, entry)
            attrs = entry.attributes || {}
            discriminated = candidates.find do |member|
              pairs = member.discriminator
              pairs && !pairs.empty? &&
                pairs.all? { |name, expected| attrs[name.to_s].to_s == expected.to_s && !attrs[name.to_s].nil? }
            end
            discriminated || candidates.find { |m| m.discriminator.nil? || m.discriminator.empty? } || candidates.first
          end
        end
      end
    end
  end
end
