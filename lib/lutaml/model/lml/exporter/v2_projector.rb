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
          def project
            reject_non_serializable!
            reject_anonymous!
            reject_custom_initialize!
            reject_reserved_member!
            mappings = project_mappings
            choices = project_choices
            {
              "lml" => 2,
              "model" => model_name(@klass),
              "register" => portable_register,
              "attributes" => @klass.attributes(@register).map { |_, attr| project_attribute(attr) },
              "mappings" => mappings,
              "ordered_content" => ordered_content_descriptor,
              "choices" => choices,
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
              next if declarative_option?(key, value)

              reason = REFERENCE_OPTIONS.include?(key) ? :unsupported_type : :unsupported_mapping
              raise RejectedError.new(reason, @klass,
                                      "attribute #{attr.name}: option #{key} has no portable form")
            end
          end

          def empty_option?(value)
            value.respond_to?(:empty?) && value.empty?
          end

          # Model choices travel as explicit, deferred validation metadata;
          # sequence choices travel in the XML compositor contract.
          def declarative_option?(key, value)
            if key == :choice
              return @model_choice_ids.key?(value) ||
                  (value.is_a?(Lutaml::Model::Choice) && value.format.to_s == "xml")
            end

            key == :polymorphic_class
          end

          def project_choices
            @model_choice_ids = {}.compare_by_identity
            groups = @klass.choice_attributes.map { |choice| project_model_choice(choice, []) }
            return if groups.empty?

            { "version" => 1, "validation" => "explicit", "groups" => groups }
          end

          def project_model_choice(choice, ancestors)
            unless choice.format.nil? || choice.format.to_s == "xml"
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "model choice format must be XML or unspecified")
            end
            if ancestors.any? { |ancestor| ancestor.equal?(choice) }
              raise RejectedError.new(:unsupported_mapping, @klass, "cyclic model choice")
            end

            min = choice.min
            max = choice.max
            unbounded = max.respond_to?(:infinite?) && max.infinite? == 1
            unless min.is_a?(::Integer) && min >= 0 &&
                (unbounded || (max.is_a?(::Integer) && max >= 0))
              raise RejectedError.new(:unsupported_type, @klass,
                                      "model choice bounds must be nonnegative integers or an unbounded maximum")
            end
            @model_choice_ids[choice] = true
            members = choice.attributes.map do |member|
              if member.is_a?(Lutaml::Model::Choice)
                { "choice" => project_model_choice(member, ancestors + [choice]) }
              else
                current = @klass.attributes(@register)[member.name]
                unless current && portable_collection(current) == portable_collection(member)
                  raise RejectedError.new(:unsupported_mapping, @klass,
                                          "model choice member #{member.name} differs from its declared attribute")
                end
                { "attribute" => member.name.to_s }
              end
            end
            { "min" => min, "max" => unbounded ? nil : max,
              "format" => choice.format&.to_s, "members" => members }
          end

          def portable_type(attr)
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
            return { "present" => false } if attr.default_kind == :none

            { "present" => true, "value" => portable_value(attr, static_default(attr), "default") }
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

          def portable_kind(attr)
            resolve_type(attr).nil? ? nil : type_name(attr)
          end

          def portable_scalar(attr, kind, value, what)
            json = json_value(attr, value, what)
            return json if json.nil?

            unless scalar_matches?(kind, json)
              raise RejectedError.new(:non_serializable_default, @klass,
                                      "attribute #{attr.name}: #{what} #{RejectedError.show(value)} is not a #{kind}")
            end

            kind == "float" ? float_wire(attr, json, what) : portable_exact(attr, json, what)
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

          # The exporter emits no bundle value_types, so a custom value
          # type could never pass the gate; refuse it by name.
          def reject_custom_value_type!(resolved, attr)
            return unless resolved.is_a?(Class) && resolved <= Lutaml::Model::Type::Value && resolved.name

            raise RejectedError.new(:unsupported_type, @klass,
                                    "attribute #{attr.name}: custom value type #{resolved.name} has no portable form")
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
          def reject_executable_rule!(rule)
            if rule.custom_methods.to_h.any?
              raise RejectedError.new(:unsupported_mapping, @klass,
                                      "rule #{Array(rule.name).first}: custom with: methods are executable")
            end
            return if rule.transform.to_h.empty?

            raise RejectedError.new(:unsupported_mapping, @klass,
                                    "rule #{Array(rule.name).first}: transform is executable")
          end

          def content_rule_extras(_rule)
            {}
          end

          def element_rule_extras(rule)
            { "discriminator" => discriminator_field(rule) }
          end

          def key_value_rule_extras(rule)
            { "root_mappings" => rule_root_mappings_field(rule),
              "discriminator" => discriminator_field(rule) }
          end

          def discriminator_field(rule)
            poly = rule.polymorphic
            return nil unless poly.is_a?(::Hash) && poly[:attribute]

            cases = (poly[:class_map] || {}).to_h do |wire, target|
              [wire.to_s, model_id(target)]
            end
            { "attribute" => poly[:attribute].to_s, "cases" => cases }
          end

          # One resolved "render" object.
          def render_fields(rule)
            { "render" => resolved_render(rule),
              "namespace" => (rule_namespace(rule) if rule.respond_to?(:namespace_param) && rule.name) }
          end

          def rule_namespace(rule)
            return { "mode" => "inherit" } if rule.namespace_param.nil? || rule.namespace_param == :inherit
            return { "mode" => "unqualified" } if rule.namespace_param == :blank || rule.namespace.nil?

            { "mode" => "uri", "uri" => rule.namespace, "prefix" => rule.prefix&.to_s }.compact
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
