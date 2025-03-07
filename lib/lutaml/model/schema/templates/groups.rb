# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module Templates
        module Groups
          extend self
          attr_accessor :groups

          GROUPS_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            class <%= klass %> < Lutaml::Model::Serializable
            <%=
              if attributes.key?(:sequence)
                attributes[:sequence].map do |attr_type, attrs|
                  case attr_type
                  when :elements
                    model_attributes(attrs, current_indent)
                  when :choice
                    model_choices(attrs, current_indent, indent)
                  when :group
                    model_groups_import(attrs, current_indent)
                  end
                end.join("\n")
              end
            %>
            <%= render_model_choice(attributes[:choice], current_indent, indent) if attributes.key?(:choice) %>
            end
          TEMPLATE

          def create_groups(groups, options: {})
            indent = options[:indent] || 2
            current_indent = options[:current_indent] || " " * indent
            groups.map do |name, attributes|
              klass = Utils.camel_case(name)
              GROUPS_TEMPLATE.result(binding)
            end
          end

          def model_attributes(attributes, current_indent)
            attributes.map { |attr| render_model_attribute(attr, current_indent) }.join("\n")
          end

          def render_model_attribute(attribute, current_indent)
            if attribute.key?(:ref_class)
              attribute = resolve_referenced_attribute(attribute)
            end

            "#{current_indent}attribute :#{attribute.element_name}, :#{resolve_element_class(attribute)}#{resolve_occurs(attribute[:arguments])}"
          end

          def resolve_referenced_attribute(attribute)
            ref_class = attribute.ref_class.split(":").last
            # TODO: Create a class for the error message
            XmlCompiler.elements[ref_class] ||
              raise("Referenced class not found: #{attribute.ref_class}")
          end

          def resolve_element_class(attribute)
            raw_klass = attribute.key?(:type_name) ? attribute.type_name : attribute.base_class
            klass = extract_class_name(raw_klass)
            case klass
            when *XmlCompiler::DEFAULT_CLASSES
              klass
            else
              Utils.snake_case(klass)
            end
          end

          def model_groups_import(groups, current_indent)
            if groups.key?(:ref_class)
              "#{current_indent}import_model(#{Utils.camel_case(extract_class_name(groups[:ref_class]))})\n"
            else
              # TODO: update this condition as it's for DEVELOPMENT PURPOSES ONLY
              raise "Group without ref_class found: #{groups.inspect}"
            end
          end

          def model_choices(choices, current_indent, indent)
            choices.map do |choice|
              render_model_choice(choice, current_indent, indent)
            end
          end

          def render_model_choice(choice, current_indent, indent)
            args = choice&.fetch(:arguments)

            if has_unsupported_keys?(choice)
              # TODO: remove this and it's relevant code as it's for DEVELOPMENT PURPOSES ONLY
              raise "Choice contains unsupported keys: #{choice.keys.select { |k| k.is_a?(Symbol) && ![:groups, :group, :arguments].include?(k.to_sym) }}"
            end

            choice_str = "#{current_indent}choice#{resolve_choice_args(args)} do\n"
            next_indent = current_indent + " " * indent

            choice.each do |attr_name, attribute|
              next if attr_name == :arguments

              choice_str += build_choice_attribute(attr_name, attribute, next_indent)
            end

            choice_str += "#{current_indent}end\n"
          end

          def build_choice_attribute(attr_name, attribute, indent)
            if attr_name == :group
              model_groups_import(attribute, indent).to_s
            elsif attr_name.is_a?(String)
              render_model_attribute(attribute, indent) + "\n"
            else
              "" # Skip unsupported attributes
            end
          end

          def has_unsupported_keys?(choice)
            choice.keys.any? { |key| key.is_a?(Symbol) && ![:groups, :group, :arguments].include?(key.to_sym) }
          end

          def extract_class_name(klass)
            klass.split(":").last
          end

          def resolve_occurs(arguments)
            return if arguments.nil? || arguments.empty?

            min_occurs = arguments[:min_occurs]
            max_occurs = arguments[:max_occurs]

            if max_occurs && max_occurs.to_s.match?(/[A-Za-z]+/)
              max_occurs = nil
            elsif max_occurs
              max_occurs = max_occurs.to_i
            end

            collection_value = max_occurs ? "#{min_occurs.to_i}..#{max_occurs}" : "true"
            ", collection: #{collection_value}"
          end

          def resolve_choice_args(args)
            return unless args&.any?

            args_arr = []
            args_arr << "min: #{args[:min_occurs]}" if args[:min_occurs]
            args_arr << "max: #{args[:max_occurs]}" if args[:max_occurs]
            "(#{args_arr.join(', ')})"
          end
        end
      end
    end
  end
end
