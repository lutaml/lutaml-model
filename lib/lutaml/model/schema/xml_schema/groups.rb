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
                  when :sequence
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

            "#{current_indent}attribute :#{Utils.snake_case(attribute.element_name)}, :#{resolve_element_class(attribute)}#{resolve_collection(attribute[:arguments])}"
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
            attrs.map do |attr|
              if attr.key?(:sequence)
                resolve_sequences(attr[:sequence], current_indent, indent)
              elsif attr.key?(:choice)
                model_choices([attr[:choice]], current_indent, indent)
              elsif attr.key?(:element_name)
                render_model_attribute(attr, current_indent)
              elsif attr.key?(:group)
                model_groups_import(attr[:group], current_indent)
              end
            end.join("\n")
          end

          def model_groups_import(groups, current_indent)
            "#{current_indent}import_model(#{Utils.camel_case(extract_class_name(groups[:ref_class]))})\n"
          end

          def model_choices(choices, current_indent, indent)
            choices.map { |choice| render_model_choice(choice, current_indent, indent) }.join("\n")
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

          def extract_elements(elements, sequence_arr, current_indent)
            case elements
            when Array
              elements.map { |element| extract_elements(element, sequence_arr, current_indent) }
            when Hash
              elements.each do |name, element|
                case name
                when String
                  sequence_arr << render_mapping_element({ element: element }, current_indent)
                end
              end
            end
          end

          def resolve_collection(arguments)
            return if arguments.nil? || arguments.empty?

            min_occurs = arguments[:min_occurs]
            max_occurs = arguments[:max_occurs]
            ", collection: #{collection_value(min_occurs, max_occurs)}"
          end

          def collection_value(min, max)
            if max && !max.to_s.match?(/[A-Za-z]+/)
              max_occurs = max.to_i
            end
            min_occurs = min.to_s.to_i
            return "true" unless min_occurs || mix_occurs

            [min_occurs, "..", max_occurs].compact.join
          end

          def render_model_sequence(attributes, current_indent, indent)
            sequence = attributes[:sequence]
            next_indent = (" " * indent) + current_indent
            sequence_arr = ["#{current_indent}sequence#{UtilityHelper.resolve_min_max_args(attributes)} do"]
            if sequence.is_a?(Array)
              sequence.each do |instance|
                if instance.keys.one?(String)
                  sequence_arr << render_mapping_element(instance, next_indent)
                elsif instance.key?(:sequence)
                  sequence_arr << render_model_sequence(instance, next_indent, indent)
                end
              end
            elsif sequence&.key?(:sequence)
              sequence[:sequence].each do |instance|
                if instance.keys.one?(String)
                  sequence_arr << render_mapping_element(instance, next_indent)
                elsif instance.key?(:sequence)
                  sequence_arr << render_model_sequence(instance, next_indent, indent)
                elsif instance.key?(:choice)
                  extract_elements(instance[:choice], sequence_arr, next_indent)
                end
              end
            elsif attributes.key?(:element_name)
              sequence_arr << render_mapping_element(attributes, current_indent)
            end
            sequence_arr << "#{current_indent}end"
            sequence_arr.join("\n")
          end

          def resolve_sequence_render(attributes, elements, current_indent, indent)
            if attributes.key?(:sequence)
              resolve_sequence_render(attributes, elements, current_indent, indent)
            elsif attributes.keys.one?(String)
              elements << attributes
            elsif attributes.key?(:choice)
              extract_elements(instance[:choice], elements)
            end
          end

          def render_mapping_elements(elements, current_indent)
            elements.reject!(&:empty?)
            elements.map do |element|
              render_mapping_element(element, current_indent)
            end.join("\n")
          end

          def render_mapping_element(element, current_indent)
            element = element.values.first
            "#{current_indent}map_element #{element.element_name.inspect}, to: :#{Utils.snake_case(element.element_name)}"
          end
        end
      end
    end
  end
end
