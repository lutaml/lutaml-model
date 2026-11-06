# frozen_string_literal: true

require "lutaml/model"
require_relative "rejected_error"
require_relative "ordered_content"

module Lutaml
  module Model
    module Lml
      # Rebuilds the XML / JSON / YAML mapping policies of a materialized
      # Ruby declaration graph from a validated neutral LML bundle
      # (lutaml-model#1033, card 03b).
      #
      #   classes = Materialization.build(bundle, ...)   # attributes (03a)
      #   MappingCompiler.apply(classes, bundle)         # mappings (here)
      #
      # Two phases keep a refusal from leaving half-declared classes:
      # `plan` translates every model's mapping documents into DSL calls
      # (raising a named RejectedError for anything with no declarative
      # Ruby form) and only then `declare` runs the DSL. Nothing is
      # evaluated from the document: rule keys are matched against a
      # closed list, policy names against closed tables, and namespaces
      # become fresh Lutaml::Xml::Namespace classes built from the
      # document's uri/prefix strings.
      #
      # Order data is not stored in the mapping: a model that declares an
      # +ordered_content+ descriptor gets an +ordered+ XML mapping (unless
      # the document already says mixed), after which OrderedContent
      # captures and applies the per-instance tokens.
      class MappingCompiler
        XML_FORMAT_KEYS = %w[root namespace rules ordered mixed_content
                             sequence].freeze
        KEY_VALUE_FORMAT_KEYS = %w[namespace rules].freeze
        XML_RULE_KEYS = %w[kind name to namespace cdata render
                           discriminator].freeze
        KEY_VALUE_RULE_KEYS = %w[key to render child_mappings
                                 discriminator].freeze
        XML_KINDS = %w[attribute element content any_attribute].freeze
        RENDER_KEYS = %w[nil empty default].freeze
        # Render policy name -> map_* option, per slot. The slot's
        # "natural" policy is the plain `true`; Ruby reads the rest as
        # symbols (see MappingRule#render_as).
        RENDER_NIL = { "omit" => false, "as_nil" => true,
                       "as_empty" => :as_empty, "as_blank" => :as_blank }.freeze
        RENDER_EMPTY = { "omit" => false, "as_empty" => true,
                         "as_nil" => :as_nil, "as_blank" => :as_blank }.freeze
        FORMATS = %w[xml json yaml].freeze

        Plan = Struct.new(:id, :klass, :format, :steps)

        # @param model_map [Hash{String=>Class}] model id => class, as
        #   returned by Materialization.build
        # @param bundle [Hash, #to_h] a validated bundle (string keys)
        # @return [Hash{String=>Class}] model_map, with mappings declared
        def self.apply(model_map, bundle)
          new(model_map, bundle).apply
        end

        def initialize(model_map, bundle)
          @model_map = model_map
          @bundle = bundle.respond_to?(:to_h) ? bundle.to_h : bundle
          @namespaces = {}
        end

        def apply
          plans = models.flat_map { |id, document| plan_model(id, document) }
          plans.each { |plan| declare(plan) }
          @model_map
        end

        private

        def models
          (@bundle["models"] || {}).sort_by { |id, _| id }
        end

        def fail!(reason, detail, id, **context)
          raise RejectedError.new(reason, nil, detail, model_id: id, **context)
        end

        # -- planning ---------------------------------------------------

        def plan_model(id, document)
          klass = @model_map.fetch(id) do
            fail!(:dangling_reference, "no class for model #{id} in the model map", id)
          end
          reject_reserved!(id, document)
          check_ordered_descriptor(id, document)
          (document["mappings"] || {}).sort_by { |format, _| format }.map do |format, mapping|
            plan_format(id, document, klass, format, mapping)
          end
        end

        def reject_reserved!(id, document)
          reserved = document["attributes"].to_a.any? { |a| a["name"] == OrderedContent::MEMBER }
          return unless reserved

          fail!(:reserved_member, "#{OrderedContent::MEMBER} is reserved for ordered content", id)
        end

        def check_ordered_descriptor(id, document)
          return unless document.key?("ordered_content")

          descriptor = document["ordered_content"]
          return if descriptor.is_a?(::Hash) && descriptor["member"] == OrderedContent::MEMBER &&
            descriptor["version"] == OrderedContent::VERSION

          fail!(:invalid_ordered_content,
                "expected {member: #{OrderedContent::MEMBER}, version: #{OrderedContent::VERSION}}", id)
        end

        def plan_format(id, document, klass, format, mapping)
          unless FORMATS.include?(format)
            fail!(:unsupported_format, "format #{format}", id, format: format)
          end
          if klass.mappings.key?(format.to_sym)
            fail!(:unsupported_mapping, "#{format} mapping already declared on the class", id,
                  format: format)
          end

          steps = if format == "xml"
                    xml_steps(id, document, mapping)
                  else
                    key_value_steps(id, document, mapping, format)
                  end
          Plan.new(id, klass, format, steps)
        end

        def only_keys!(id, node, allowed, format, where)
          extra = node.keys - allowed
          return if extra.empty?

          fail!(:unsupported_mapping, "#{where}: no declarative form for #{extra.sort.join(', ')}", id,
                format: format)
        end

        def attribute_names(document)
          document["attributes"].to_a.map { |a| a["name"] }
        end

        # -- XML ----------------------------------------------------------

        def xml_steps(id, document, mapping)
          only_keys!(id, mapping, XML_FORMAT_KEYS, "xml", "mapping")
          reject_sequence!(id, mapping)
          steps = []
          root = mapping["root"]
          unless root.nil? || (root.is_a?(::Hash) && (root["element"].nil? || root["element"].is_a?(::String)))
            fail!(:invalid_document, "xml root must be an object with a string element", id, format: "xml")
          end
          steps << [:element, [root["element"]], {}] if root && root["element"]
          steps.concat(order_steps(document, mapping))
          steps.concat(namespace_steps(id, mapping["namespace"], "xml"))
          known = attribute_names(document)
          mapping.fetch("rules", []).each_with_index do |rule, index|
            steps << xml_rule_step(id, rule, index, known)
          end
          steps
        end

        def reject_sequence!(id, mapping)
          return if mapping["sequence"].nil? || mapping["sequence"].empty?

          fail!(:unsupported_mapping, "sequence/choice compositors have no Ruby reconstruction yet", id,
                format: "xml")
        end

        # mixed (root.mixed or mixed_content) implies ordered; a model
        # that declares per-instance order data needs an ordered mapping.
        def order_steps(document, mapping)
          mixed = mapping["mixed_content"] || mapping["root"]&.fetch("mixed", nil)
          return [[:mixed_content, [], {}]] if mixed
          return [[:ordered, [], {}]] if mapping["ordered"] || document.key?("ordered_content")

          []
        end

        def xml_rule_step(id, rule, index, known)
          where = "rules/#{index}"
          only_keys!(id, rule, XML_RULE_KEYS, "xml", where)
          kind = rule["kind"]
          unless XML_KINDS.include?(kind)
            fail!(:unsupported_mapping, "#{where}: rule kind #{RejectedError.show(kind)}", id, format: "xml")
          end
          return any_attribute_step(id, rule, known, where) if kind == "any_attribute"

          to = target(id, rule, known, where, "xml", required: kind != "content")
          options = { to: to }.compact
          options.merge!(render_options(id, rule["render"], where, "xml"))
          return content_step(id, rule, options, where) if kind == "content"

          rule_step(id, rule, kind, options, where)
        end

        def any_attribute_step(id, rule, known, where)
          only_keys!(id, rule, %w[kind to], "xml", where)
          [:map_all_attributes, [], { to: target(id, rule, known, where, "xml") }]
        end

        def content_step(id, rule, options, where)
          reject_content_extras!(id, rule, where)
          options[:cdata] = true if rule["cdata"]
          [:map_content, [], options]
        end

        def reject_content_extras!(id, rule, where)
          extras = %w[name discriminator namespace].select { |key| rule.key?(key) }
          return if extras.empty?

          fail!(:unsupported_mapping, "#{where}: content rule cannot carry #{extras.join(', ')}", id,
                format: "xml")
        end

        def rule_step(id, rule, kind, options, where)
          names = names_of(id, rule["name"], where, "xml")
          if kind == "attribute"
            fail!(:unsupported_mapping, "#{where}: cdata on an attribute", id, format: "xml") if rule["cdata"]
            fail!(:unsupported_mapping, "#{where}: discriminator on an attribute", id, format: "xml") if rule["discriminator"]
          else
            options[:cdata] = true if rule["cdata"]
            poly = polymorphic(id, rule["discriminator"], where, "xml")
            options[:polymorphic] = poly if poly
          end
          namespace_option(id, rule["namespace"], where, options)
          [kind == "attribute" ? :map_attribute : :map_element, [names], options]
        end

        # A rule namespace is either the model's own (inherit — what the
        # DSL does when nothing is said) or an explicit opt-out. Ruby's
        # DSL refuses any other namespace at rule level, so a uri mode is
        # a named rejection rather than a silent drop.
        def namespace_option(id, node, where, options)
          return if node.nil?

          case node["mode"]
          when "inherit" then nil
          when "unqualified" then options[:namespace] = nil
          else
            fail!(:unsupported_mapping,
                  "#{where}: rule-level namespace #{node['mode']} is not expressible in the Ruby mapping DSL",
                  id, format: "xml")
          end
        end

        def names_of(id, names, where, format)
          unless names.is_a?(::Array) && !names.empty? && names.all?(::String)
            fail!(:invalid_document, "#{where}: name/key must be a non-empty string array", id, format: format)
          end
          names.length == 1 ? names.first : names
        end

        def target(id, rule, known, where, format, required: true)
          to = rule["to"]
          if to.nil?
            return nil unless required

            fail!(:unsupported_mapping, "#{where}: rule has no `to` (custom with: methods are executable)", id,
                  format: format)
          end
          unless known.include?(to)
            fail!(:dangling_reference, "#{where}: `to` #{RejectedError.show(to)} is not an attribute of the model", id,
                  format: format)
          end
          to.to_sym
        end

        # -- key-value ----------------------------------------------------

        def key_value_steps(id, document, mapping, format)
          only_keys!(id, mapping, KEY_VALUE_FORMAT_KEYS, format, "mapping")
          namespace_steps(id, mapping["namespace"], format)
          known = attribute_names(document)
          mapping.fetch("rules", []).each_with_index.map do |rule, index|
            key_value_rule_step(id, rule, index, known, format)
          end
        end

        def key_value_rule_step(id, rule, index, known, format)
          where = "rules/#{index}"
          only_keys!(id, rule, KEY_VALUE_RULE_KEYS, format, where)
          options = { to: target(id, rule, known, where, format) }
          options.merge!(render_options(id, rule["render"], where, format))
          poly = polymorphic(id, rule["discriminator"], where, format)
          options[:polymorphic] = poly if poly
          options[:child_mappings] = symbolize(rule["child_mappings"]) if rule["child_mappings"]
          [:map, [names_of(id, rule["key"], where, format)], options]
        end

        def symbolize(node)
          case node
          when ::Hash then node.to_h { |key, value| [key.to_sym, symbolize(value)] }
          when ::Array then node.map { |item| symbolize(item) }
          when ::String then node.to_sym
          else node
          end
        end

        # -- shared pieces ------------------------------------------------

        def namespace_steps(id, node, format)
          return [] if node.nil? || node["mode"] == "inherit"
          return [[:namespace, [:blank], {}]] if node["mode"] == "unqualified" && format == "xml"

          if node["mode"] == "uri" && format == "xml"
            return [[:namespace, [namespace_class(node["uri"], node["prefix"])], {}]]
          end

          fail!(:unsupported_mapping, "namespace #{node['mode']} on a #{format} mapping", id, format: format)
        end

        def namespace_class(uri, prefix)
          unless prefix.nil? || prefix.is_a?(::String)
            fail!(:invalid_document, "namespace prefix must be a string", nil, format: "xml")
          end
          @namespaces[[uri, prefix]] ||= Class.new(Lutaml::Xml::Namespace) do
            uri(uri)
            prefix_default(prefix) if prefix
          end
        end

        # render {nil, empty, default}: absent slots keep the documented
        # Ruby default (never guessed truthiness).
        def render_options(id, render, where, format)
          return {} if render.nil?

          extra = render.keys - RENDER_KEYS
          unless extra.empty?
            fail!(:unsupported_mapping, "#{where}: render #{extra.sort.join(', ')}", id, format: format)
          end
          options = {}
          options[:render_nil] = render_policy(id, RENDER_NIL, render["nil"], where, format) if render.key?("nil")
          options[:render_empty] = render_policy(id, RENDER_EMPTY, render["empty"], where, format) if render.key?("empty")
          if render.key?("default")
            unless [true, false].include?(render["default"])
              fail!(:unsupported_mapping, "#{where}: render default must be boolean", id, format: format)
            end
            options[:render_default] = render["default"]
          end
          options
        end

        def render_policy(id, table, name, where, format)
          return table.fetch(name) if table.key?(name)

          fail!(:unsupported_mapping, "#{where}: render policy #{RejectedError.show(name)}", id, format: format)
        end

        # Ruby resolves class_map values with Object.const_get(string),
        # so a polymorphic target must be an installed, reachable
        # constant; an anonymous or detached class has no such name.
        def polymorphic(id, discriminator, where, format)
          return nil if discriminator.nil?

          cases = discriminator["cases"].to_h do |wire, target_id|
            [wire, constant_name(id, target_id, where, format)]
          end
          # String key: Ruby looks the wire value up with `value[attribute]`
          # on parsed (string-keyed) data, so a symbol never matches.
          { attribute: discriminator["attribute"], class_map: cases }
        end

        def constant_name(id, target_id, where, format)
          klass = @model_map[target_id]
          if klass.nil?
            fail!(:unknown_discriminator, "#{where}: case target #{target_id} is not in the model map", id,
                  format: format)
          end
          name = klass.name
          return name if installed_constant?(name, klass)

          fail!(:unsupported_mapping,
                "#{where}: polymorphic target #{target_id} needs an installed constant " \
                "(Ruby resolves class_map by Object.const_get)", id, format: format)
        end

        def installed_constant?(name, klass)
          !name.nil? && Object.const_get(name).equal?(klass)
        rescue NameError
          false
        end

        # -- declaration --------------------------------------------------

        def declare(plan)
          steps = plan.steps
          plan.klass.public_send(plan.format) do
            steps.each { |name, args, options| public_send(name, *args, **options) }
          end
        rescue Lutaml::Model::IncorrectMappingArgumentsError, Lutaml::Xml::Error::InvalidNamespaceError => e
          raise RejectedError.new(:unsupported_mapping, nil, e.message, model_id: plan.id, format: plan.format)
        end
      end
    end
  end
end
