# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlSchema
        module Groups
          extend self
          attr_accessor :groups

          GROUPS_TEMPLATE = ERB.new(<<~TEMPLATE, trim_mode: "-")
            # frozen_string_literal: true

            require "lutaml/model"
            <%=
              UtilityHelper.resolve_required_files(content).join("\n") + "\n"
            -%>
            class <%= Utils.camel_case(name) %> < Lutaml::Model::Serializable
            <%=
              if content.key?(:sequence)
                content[:sequence].map do |attr_type, attrs|
                  case attr_type
                  when :elements
                    model_attributes(attrs, current_indent)
                  when :choice
                    model_choices(attrs, current_indent, indent)
                  when :group
                    model_groups_import(attrs, current_indent)
                  when :sequences
                    resolve_sequences(attrs, current_indent, indent)
                  end
                end.join("\n")
              end
            %>
            <%= render_model_choice(content[:choice], current_indent, indent) if content.key?(:choice) %>
            <%= "\#{current_indent}xml do" %>
            <%=
              mapping_indent = (" " * indent) + current_indent
              "\#{mapping_indent}no_root\n"
            %>
            <%=
              render_model_sequence(content, mapping_indent, indent) if content.key?(:sequence)
            %>
            <%= "\#{current_indent}end\n" -%>
            end
          TEMPLATE

          def create_groups(groups, options: {})
            @groups = MappingHash.new
            indent = options[:indent] || 2
            current_indent = options[:current_indent] || (" " * indent)
            groups.map do |name, content|
              @groups[Utils.snake_case(name)] = GROUPS_TEMPLATE.result(binding)
            end
            @groups
          end

          def model_attributes(attributes, current_indent)
            attributes.map { |attr| render_model_attribute(attr, current_indent) }.join("\n")
          end

          def render_model_attribute(attribute, current_indent)
            if attribute.key?(:ref_class)
              attribute = XmlSchema.elements[extract_class_name(attribute.ref_class).to_sym]
            end

            "#{current_indent}attribute :#{Utils.snake_case(attribute.element_name)}, :#{resolve_element_class(attribute)}#{resolve_occurs(attribute[:arguments])}"
          end

          def resolve_element_class(attribute)
            raw_klass = attribute.key?(:type_name) ? attribute.type_name : attribute.base_class
            klass = extract_class_name(raw_klass)
            case klass
            when *XmlSchema::DEFAULT_CLASSES
              klass
            else
              Utils.snake_case(klass)
            end
          end

          def resolve_sequences(attrs, current_indent, indent)
            case attrs
            when MappingHash
              attrs.map do |attr_type, attr_content|
                case attr_type
                when :sequences
                  resolve_sequences(attr_content, current_indent, indent)
                when :choice
                  model_choices(attr_content, current_indent, indent)
                when :elements
                  model_attributes(attr_content, current_indent)
                when :group
                  model_groups_import(attr_content, current_indent)
                end
              end.join("\n")
            when Array
              attrs.map { |attr| resolve_sequences(attr, current_indent, indent) }.join("\n")
            end
          end

          def model_groups_import(groups, current_indent)
            "#{current_indent}import_model(#{Utils.camel_case(extract_class_name(groups[:ref_class]))})\n"
          end

          def model_choices(choices, current_indent, indent)
            choices.map { |choice| render_model_choice(choice, current_indent, indent) }
          end

          def render_model_choice(choice, current_indent, indent)
            choice_arr = ["#{current_indent}choice#{UtilityHelper.resolve_min_max_args(choice)} do"]
            next_indent = current_indent + (" " * indent)
            choice.each do |attr_name, attribute|
              next if attr_name == :arguments

              choice_arr << build_choice_attribute(attr_name, attribute, next_indent)
            end
            choice_arr << "#{current_indent}end"
            choice_arr.join("\n")
          end

          def build_choice_attribute(attr_name, attribute, indent)
            if attr_name == :group
              model_groups_import(attribute, indent).to_s
            elsif attr_name.is_a?(String)
              render_model_attribute(attribute, indent)
            end
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

          def render_model_sequence(attributes, current_indent, indent)
            sequence = attributes[:sequence]
            next_indent = (" " * indent) + current_indent
            sequence_arr = ["#{current_indent}sequence#{UtilityHelper.resolve_min_max_args(sequence)} do"]
            if sequence.key_exist?(:sequences)
              sequence[:sequences].each do |seq|
                sequence_arr << render_model_sequence({ sequence: seq }, next_indent, indent)
              end
            end
            elements = sequence_elements(sequence)
            sequence_arr << render_mapping_elements(elements, next_indent) if elements.any?
            sequence_arr << "#{current_indent}end"
            sequence_arr.join("\n")
          end

          def sequence_elements(sequence, elements = [])
            elements += sequence.elements if sequence.key_exist?(:elements)
            elements += sequence.choice.map(&:values).flatten if sequence.key_exist?(:choice)
            elements
          end

          def render_mapping_elements(elements, current_indent)
            elements.reject!(&:empty?)
            elements.map do |element|
              "#{current_indent}map_element #{element.element_name.inspect}, to: :#{Utils.snake_case(element.element_name)}"
            end.join("\n")
          end
        end
      end
    end
  end
end
