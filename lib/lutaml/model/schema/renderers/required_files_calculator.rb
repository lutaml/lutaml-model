# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Renderers
        # Computes the `require_relative` / `require` lines that a
        # generated Definitions::Model needs at the top of its file.
        #
        # XSD and RNG have different strategies because their type
        # references mean different things:
        #
        # - XSD attributes carry TypeRef(:w3c | :symbol | :class_ref):
        #     :w3c       -> require "lutaml/xml/w3c"
        #     :symbol    -> require_relative "<value>"
        #                    (unless the value is a skippable built-in)
        #                    decimal is special: require "bigdecimal"
        #     :class_ref -> no require (class is autoloaded by registry)
        #   Plus any required_files surfaced by simple_content + the
        #   namespace class.
        #
        # - RNG attributes only ever reference other generated classes
        #   via :class_ref, so the calculator only collects class names
        #   (imports + class_ref types + namespace) and the caller
        #   formats them as `require_relative "snake_case_name"`.
        module RequiredFilesCalculator
          module_function

          # XSD strategy. `skippable_type?` is a one-arg predicate the
          # caller supplies so the calculator doesn't have to know the
          # XSD built-in type table.
          def for_xml(model, skippable_type:)
            deps = []
            Definitions::MemberWalk.each_attribute(model.members) do |attr|
              deps.concat(xml_attribute_requires(attr, skippable_type))
            end
            deps.concat(simple_content_requires(model.simple_content, skippable_type))
            deps << namespace_require(model.namespace_class_name) if model.namespace_class_name
            deps.uniq
          end

          # RNG strategy. Returns the de-duplicated list of generated-class
          # names the model depends on; caller wraps as `require_relative`.
          def class_names_for_rng(model)
            deps = model.imports.dup
            Definitions::MemberWalk.each_attribute(model.members) do |attr|
              deps << attr.type.value if attr.type.kind == :class_ref
            end
            deps << model.namespace_class_name if model.namespace_class_name
            deps.uniq
          end

          def namespace_require(class_name)
            %(require_relative "#{Utils.snake_case(class_name)}")
          end

          def xml_attribute_requires(attr, skippable_type)
            ref = attr.type
            return [] unless ref

            case ref.kind
            when :w3c       then ['require "lutaml/xml/w3c"']
            when :symbol    then xml_symbol_requires(ref.value, skippable_type)
            when :class_ref then []
            else []
            end
          end

          def xml_symbol_requires(value, skippable_type)
            return [%(require "bigdecimal")] if value == "decimal"
            return [] if skippable_type.call(value)

            [%(require_relative "#{value}")]
          end

          # base_class arrives as a raw XSD name (e.g. "xs:dateTime"). The
          # built-in skippable check keys on the XSD spelling (`:dateTime`),
          # not the snake_case file form, so test against `local` directly
          # before emitting the require_relative.
          def simple_content_requires(simple_content, skippable_type)
            return [] if simple_content.nil? || simple_content.base_class.nil?

            local = Utils.last_of_split(simple_content.base_class)
            return [%(require "bigdecimal")] if local == "decimal"
            return [] if skippable_type.call(local)

            [%(require_relative "#{Utils.snake_case(local)}")]
          end
        end
      end
    end
  end
end
