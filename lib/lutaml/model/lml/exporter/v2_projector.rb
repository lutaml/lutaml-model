# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      class Exporter
        # The portable v2 model document (lutaml-model#1033 contract in
        # 01-DOCUMENT-CONTRACT): tagged types, typed defaults, resolved
        # render policies, namespace modes, discriminators and the
        # ordered-content descriptor. Everything with no portable slot is
        # refused by name instead of silently dropped.
        class V2Projector < Exporter
          HOOK_DIRECTIONS = %i[to from].freeze

          def project
            reject_non_serializable!
            reject_anonymous!
            reject_reserved_member!
            @used_value_types = {}
            mappings = project_mappings
            attributes = @klass.attributes(@register).map { |_, attr| project_attribute(attr) }
            {
              "lml" => 2,
              "model" => model_name(@klass),
              "register" => portable_register,
              "custom_initialize" => (true if custom_initialize?),
              "attributes" => attributes,
              "value_types" => (@used_value_types.sort.to_h unless @used_value_types.empty?),
              "mappings" => mappings,
              "ordered_content" => ordered_content_descriptor,
            }.compact
          end

          private

          def project_attribute(attr)
            reject_unportable_options!(attr)
            {
              "name" => attr.name.to_s,
              "type" => portable_type(attr),
              "required" => attr.options[:required] ? true : false,
              "collection" => portable_collection(attr),
              "default" => portable_default(attr),
              "initialize_empty" => attr.initialize_empty? == true,
              "values" => portable_enum(attr),
              "reference" => reference_field(attr),
            }.compact
          end

          def reject_unportable_options!(attr)
            attr.options.each do |key, value|
              next if PORTABLE_ATTRIBUTE_OPTIONS.include?(key)
              next if value.nil? || value.equal?(false) || empty_option?(value)
              next if declarative_option?(key, value, attr.name)

              reason = REFERENCE_OPTIONS.include?(key) ? :unsupported_type : :unsupported_mapping
              raise RejectedError.new(reason, @klass,
                                      "attribute #{attr.name}: option #{key} has no portable form")
            end
          end

          def empty_option?(value)
            value.respond_to?(:empty?) && value.empty?
          end

          # Carried by the mapping contract, not the attribute: the XML
          # `sequence { choice {} }` compositor (its bounds travel in the
          # mapping's choice member) and the polymorphic_class marker (the
          # rule's polymorphic_map). A model-level `choice {}` block is
          # validation behaviour with no portable slot.
          def declarative_option?(key, value, attr_name = nil)
            return @klass.choice_attributes.none? { |c| c.equal?(value) } if key == :choice
            return value == true && polymorphic_rule_target?(attr_name) if key == :polymorphic

            key == :polymorphic_class
          end

          # `polymorphic: true` on an attribute is carried by the rules that
          # target it (their discriminator), so it exports only when one does.
          def polymorphic_rule_target?(attr_name)
            @klass.mappings.keys.any? do |format|
              mapping = @klass.mappings_for(format, @register)
              mapping.respond_to?(:mappings) && !mapping.respond_to?(:root_element) &&
                mapping.mappings.any? { |rule| rule.to == attr_name && rule.polymorphic.is_a?(::Hash) }
            end
          end

          def portable_type(attr)
            if (id = registered_value_type(attr))
              @used_value_types[id] = @value_types.definition(id)
              return { "kind" => "value", "id" => id }
            end

            name = type_name(attr)
            resolved = resolve_type(attr)
            return { "kind" => "model", "id" => model_id(resolved) } if resolved && name == model_name(resolved)

            { "kind" => "builtin", "name" => name }
          end

          def portable_collection(attr)
            return custom_collection(attr) if attr.options[:collection].is_a?(Class)

            field = collection_field(attr)
            return false if field.nil?
            return { "min" => 0, "max" => nil } if field == true

            { "min" => field["min"], "max" => field["max"] }
          end

          # A custom collection class travels by name (an importer supplies
          # the trusted binding); an unnameable one has no portable form.
          def custom_collection(attr)
            name = attr.options[:collection].name
            if name.nil? || name.empty?
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "attribute #{attr.name}: an anonymous collection class has no portable name")
            end

            { "min" => 0, "max" => nil, "class" => name }
          end

          def portable_default(attr)
            bound = bound_default(attr)
            return bound if bound
            return { "present" => false } if attr.default_kind == :none

            { "present" => true, "value" => portable_value(attr, static_default(attr), "default") }
          end

          # A caller-supplied constant for an opaque (Proc or delegated)
          # default. The default itself is never called; the constant goes
          # through the same type, facet and shape checks as a declared one.
          def bound_default(attr)
            model = model_id(@klass)
            return nil unless @default_bindings.key?(model, attr.name.to_s)

            kind = attr.default_kind
            unless %i[proc delegate].include?(kind)
              raise RejectedError.new(:invalid_document, @klass,
                                      "attribute #{attr.name}: a default binding targets " \
                                      "#{kind == :static ? 'a declared constant default' : 'an attribute with no default'}; " \
                                      "bindings supply only Proc or delegated defaults")
            end

            constant = @default_bindings.value(model, attr.name.to_s)
            { "present" => true, "value" => portable_value(attr, constant, "default") }
          end

          def portable_enum(attr)
            values = attr.enum_values
            return nil if values.nil? || values.empty?

            values.to_a.map { |value| portable_value(attr, value, "values") }
          end

          # A default or enum value as the JSON scalar (or array/object of
          # scalars) the declared type can express; anything else is refused
          # at export rather than failing the bundle later.
          def portable_value(attr, value, what)
            kind = portable_kind(attr)
            if kind == "float" && what == "default" && (value.nil? || value.is_a?(::Array))
              # The importer reads a float default as one canonical string:
              # no null and no collection of floats.
              refuse_value(attr, value, what)
            end
            if attr.collection? && what == "default" && value.is_a?(::Array)
              return value.map { |item| portable_scalar(attr, kind, item, what) }
            end

            portable_scalar(attr, kind, value, what)
          end

          # A registered value type's values are written as its declared
          # builtin base, so defaults and enums are checked against that.
          def portable_kind(attr)
            if (id = registered_value_type(attr))
              return @value_types.base(id)
            end

            resolve_type(attr).nil? ? nil : type_name(attr)
          end

          # The ID the caller registered for exactly this attribute's class;
          # nil for builtins, models and unregistered classes (which keep
          # their existing refusal).
          def registered_value_type(attr)
            resolved = resolve_type(attr)
            resolved.is_a?(Class) ? @value_types.id_for(resolved) : nil
          end

          def portable_scalar(attr, kind, value, what)
            json = json_value(attr, value, what)
            return json if json.nil?

            unless scalar_matches?(kind, json)
              raise RejectedError.new(:non_serializable_default, @klass,
                                      "attribute #{attr.name}: #{what} #{RejectedError.show(value)} is not a #{kind}")
            end

            exact = kind == "float" ? float_wire(attr, json, what) : portable_exact(attr, json, what)
            check_facets!(attr, exact, what)
            exact
          end

          # A registered type's default must satisfy its declared facets.
          def check_facets!(attr, json, what)
            id = what == "default" ? registered_value_type(attr) : nil
            return unless id

            problem = @value_types.facet_violation(id, json)
            return unless problem

            raise RejectedError.new(:non_serializable_default, @klass, "attribute #{attr.name}: default #{problem}")
          end

          # The importer refuses a JSON float anywhere but a float-typed value
          # and an integer outside +-(2**53 - 1); refuse both here instead of
          # exporting a bundle that cannot be imported.
          def portable_exact(attr, json, what)
            case json
            when ::Float then refuse_value(attr, json, what)
            when ::Integer
              refuse_value(attr, json, what) if json.abs > DocumentValidator::MAX_SAFE_INTEGER
            when ::Array then json.each { |item| portable_exact(attr, item, what) }
            when ::Hash then json.each_value { |item| portable_exact(attr, item, what) }
            end
            json
          end

          def scalar_matches?(kind, json)
            return json.is_a?(::Numeric) if kind == "float"

            DocumentValidator.default_shape?(kind, json)
          end

          def float_wire(attr, json, what)
            refuse_value(attr, json, what) unless json.to_f.finite?

            DocumentValidator.float_wire(json)
          end

          def json_value(attr, value, what)
            case value
            when nil, true, false, ::Integer then value
            when ::String then portable_string(attr, value, what)
            when ::Symbol then portable_string(attr, value.to_s, what)
            when ::Float
              return value if value.finite?

              refuse_value(attr, value, what)
            when ::Date, ::Time then value.iso8601
            when ::BigDecimal then value.to_s("F")
            when ::Rational then value.to_s
            when ::Array then value.map { |item| json_value(attr, item, what) }
            when ::Hash then value.to_h { |k, v| [portable_string(attr, k.to_s, what), json_value(attr, v, what)] }
            else refuse_value(attr, value, what)
            end
          end

          def portable_string(attr, string, what)
            return string if DocumentValidator.portable_string?(string)

            raise RejectedError.new(:non_serializable_default, @klass,
                                    "attribute #{attr.name}: #{what} #{RejectedError.show(string)} is not valid UTF-8")
          end

          def refuse_value(attr, value, what)
            raise RejectedError.new(:non_serializable_default, @klass,
                                    "attribute #{attr.name}: #{what} #{RejectedError.show(value)} has no JSON form")
          end

          # A custom value type is portable only when the caller registered
          # it (Exporter::ValueTypeRegistry); otherwise it is refused by name.
          def reject_custom_value_type!(resolved, attr)
            return unless resolved.is_a?(Class) && resolved <= Lutaml::Model::Type::Value && resolved.name

            raise RejectedError.new(:unsupported_type, @klass,
                                    "attribute #{attr.name}: custom value type #{resolved.name} has no portable form " \
                                    "(register it with value_types: to export it)")
          end

          # Derived formats are dropped when identical to their json/yaml
          # twin, else refused.
          def finish_mappings!(projected)
            DERIVED_FORMATS.each { |format| drop_derived_format!(projected, format) }
          end

          def drop_derived_format!(projected, format)
            return unless projected.key?(format)

            twin = projected["json"] || projected["yaml"]
            unless twin && projected[format] == twin
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "format #{format} has no portable form")
            end
            projected.delete(format)
          end

          def namespace_fields(mapping)
            { "namespace" => mapping_namespace(mapping) }
          end

          def mapping_namespace(mapping)
            return { "mode" => "inherit" } if mapping.namespace_uri.nil?

            { "mode" => "uri", "uri" => mapping.namespace_uri,
              "prefix" => mapping.namespace_prefix }.compact
          end

          # map_all_attributes: {kind:"any_attribute", to:<hash attribute>}.
          # The optional `matching:` filter is a Ruby Regexp with no
          # portable form, so it is refused by name instead of dropped.
          def any_attribute_rule(mapping)
            rule = mapping.respond_to?(:all_attributes_rule) ? mapping.all_attributes_rule : nil
            return nil if rule.nil?

            if rule.matching
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "map_all_attributes matching: #{RejectedError.show(rule.matching)} has no portable form")
            end
            { "kind" => "any_attribute", "to" => rule.to.to_s }
          end

          # Executable rule parts have no portable form; refuse without
          # calling them.
          # A rule's `with:` methods travel as hook NAMES (see custom_field),
          # key-value and xml rules alike; only a transform has no form.
          def reject_executable_rule!(rule, **)
            return if rule.transform.to_h.empty?

            raise RejectedError.new(:unsupported_mapping, @klass,
                                    "rule #{Array(rule.name).first}: transform is executable")
          end

          def content_rule_extras(rule)
            { "custom" => custom_field(rule) }
          end

          def element_rule_extras(rule)
            { "custom" => custom_field(rule), "discriminator" => discriminator_field(rule) }
          end

          def key_value_rule_extras(rule)
            { "root_mappings" => rule_root_mappings_field(rule),
              "custom" => custom_field(rule),
              "discriminator" => discriminator_field(rule) }
          end

          # The hook names of a rule's `with: {to:, from:}`; the methods are
          # never looked up, called or read.
          def custom_field(rule)
            methods = rule.custom_methods.to_h
            return nil if methods.empty?

            hooks = methods.slice(:to, :from).transform_keys(&:to_s)
              .reject { |_, name| name.to_s.start_with?(HandwrittenSerialization::ABSENT_PREFIX) }
            if hooks.empty? || (methods.keys - HOOK_DIRECTIONS).any?
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "rule #{Array(rule.name).first}: custom methods other than to/from have no portable form")
            end

            hooks.to_h do |direction, name|
              unless name.is_a?(::Symbol) || name.is_a?(::String)
                raise RejectedError.new(:unsupported_mapping, @klass,
                                        "rule #{Array(rule.name).first}: #{direction} hook is not a method name")
              end
              [direction, name.to_s]
            end
          end

          def discriminator_field(rule)
            poly = rule.polymorphic
            return nil unless poly.is_a?(::Hash) && poly[:attribute]

            map = poly[:class_map] || {}
            table = dynamic_class_map?(map) ? bound_cases(rule) : static_cases(rule, map)
            { "attribute" => poly[:attribute].to_s, "cases" => table.to_h { |wire, target| [wire.to_s, model_id(target)] } }
          end

          # A class map that fills itself through a default Proc is not a
          # finite declaration; its current contents are an accident of use.
          def dynamic_class_map?(map)
            map.respond_to?(:default_proc) && !map.default_proc.nil?
          end

          def static_cases(rule, map)
            key = rule_key(rule)
            if @polymorphic_bindings.key?(model_id(@klass), @format, key)
              raise RejectedError.new(:invalid_document, @klass,
                                      "rule #{key}: a polymorphic binding targets a static class map; " \
                                      "bindings replace only dynamic (default Proc) maps")
            end

            map
          end

          def bound_cases(rule)
            key = rule_key(rule)
            id = model_id(@klass)
            unless @polymorphic_bindings.key?(id, @format, key)
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "rule #{key} (#{@format}): the polymorphic class map is dynamic (a default Proc), " \
                                      "so its cases are not a finite declaration; supply polymorphic_bindings")
            end

            @polymorphic_bindings.cases(id, @format, key)
          end

          def rule_key(rule)
            Array(rule.name).first.to_s
          end

          # One resolved "render" object.
          def render_fields(rule)
            { "render" => resolved_render(rule),
              "namespace" => (rule_namespace(rule) if rule.respond_to?(:namespace_param) && rule.name) }
          end

          # The namespace a rule really serializes in. Explicit rule overrides
          # (:inherit, :blank, a namespace class) keep their meaning; every
          # other rule is resolved with the same public resolver and the same
          # form defaults the XML serializer uses, so a type-level namespace
          # (xml:id) or an unqualified string element of a namespaced model is
          # stated rather than assumed to inherit. Model-typed members keep
          # "inherit": the child model's own mapping names its namespace.
          def rule_namespace(rule)
            return { "mode" => "inherit" } if rule.namespace_param == :inherit
            return { "mode" => "unqualified" } if rule.namespace_param == :blank
            if rule.namespace_set? && rule.namespace_class
              return { "mode" => "uri", "uri" => rule.namespace, "prefix" => rule.prefix&.to_s }.compact
            end

            resolved_rule_namespace(rule)
          end

          def resolved_rule_namespace(rule)
            attr = rule.to && @klass.attributes(@register)[rule.to.to_sym]
            return { "mode" => "inherit" } if attr.nil? || model_member?(attr)

            parent = @xml_mapping&.namespace_class
            parent_uri = @xml_mapping&.namespace_uri
            form_default = (rule.attribute ? parent&.attribute_form_default : parent&.element_form_default) || :unqualified
            found = rule.resolve_namespace(attr: attr, register: @register, parent_ns_uri: parent_uri,
                                           parent_ns_class: parent, form_default: form_default)
            qualified_namespace(rule, found, parent_uri)
          end

          def model_member?(attr)
            type = resolve_type(attr)
            type.is_a?(Class) && type.include?(SERIALIZABLE_BASE)
          end

          def qualified_namespace(rule, found, parent_uri)
            uri = found[:uri]
            if rule.attribute
              return { "mode" => "inherit" } if uri.nil? || found[:unqualified_same_ns]
            elsif uri.nil?
              return { "mode" => parent_uri ? "unqualified" : "inherit" }
            elsif uri == parent_uri
              return { "mode" => "inherit" }
            end

            { "mode" => "uri", "uri" => uri, "prefix" => found[:prefix]&.to_s }.compact
          end

          def resolved_render(rule)
            to = rule.value_map(:to)
            {
              "nil" => RENDER_NAMES.fetch(to[:nil]),
              "empty" => RENDER_NAMES.fetch(to[:empty]),
              "default" => rule.render_default ? true : false,
            }
          end

          def rule_root_mappings_field(rule)
            root_mappings = rule.respond_to?(:root_mappings) ? rule.root_mappings : nil
            return nil unless root_mappings.is_a?(::Hash) && root_mappings.any?

            root_mappings.to_h { |key, value| [key.to_s, canonicalize_value(value)] }
          end
        end
      end
    end
  end
end
