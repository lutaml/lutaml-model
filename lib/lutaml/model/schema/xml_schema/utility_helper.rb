# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlSchema
        module UtilityHelper
          extend self

          DEFAULT_CLASSES = %w[string integer int boolean date].freeze

          UNIMPLEMENTED_REQUIRED_FILES_RESOLVER = <<~TEMPLATE
            requiring_files = UtilityHelper.resolve_required_files(content)
            requiring_files.join("\n") + "\n" if requiring_files&.any?
          TEMPLATE
          NOT_IMPLEMENTED = <<~TEMPLATE
            if content&.key_exist?(:complex_content)
              resolve_complex_content(content.complex_content).map do |element_name, element|
                if element_name == :attributes
                  element.map { |attribute| "  attribute :\#{Utils.snake_case(attribute.name)}, \#{resolve_attribute_class(attribute)}\#{resolve_attribute_default(attribute.default) if attribute.key_exist?(:default)}" }.join("\n")
                else
                  element = @elements[element.ref_class.split(":")&.last] if element&.key_exist?(:ref_class)
                  next if element[:type_name]

                  "  attribute :\#{Utils.snake_case(element_name)}, \#{resolve_element_class(element)}\#{resolve_occurs(element.arguments) if element.key_exist?(:arguments)}"
                end
              end.join("\n")
              output + "\n" if output && !output&.empty?
            end
          TEMPLATE

          def render_definition_content(content, options)
            current_indent = options[:current_indent]
            indent = options[:indent]
            content.compact.map do |key, value|
              next if key == :mixed

              case key
              when :attributes
                render_attributes_definition(value, current_indent, indent)
              when :elements
                render_elements_definition(value, current_indent, indent)
              when :groups
                render_groups_definition(value, current_indent, indent)
              when :choice
                render_choice_definition(value, current_indent, indent)
              when :sequence
                render_sequence_definition(value, current_indent, indent)
              end
            end.join("\n")
          end

          def render_sequence_definition(sequence, current_indent, indent)
            sequence.map do |instance|
              if instance.keys.one?(String)
                render_elements_definition([instance], current_indent, indent)
              elsif instance.key?(:groups)
                render_groups_definition([instance[:groups]], current_indent, indent)
              else
                binding.irb
              end
            end.join("\n")
          end

          def resolve_sequence_definition_content(content, current_indent, indent)
            content.map do |instance|
              if instance.keys.one?(String)
                instance = instance.values.first
                render_attribute_definition(instance.element_name, instance.type_name, instance[:arguments], current_indent)
              elsif instance.key?(:groups)
                render_groups_definition([instance[:groups]], current_indent, indent)
              end
            end
          end

          def render_groups_definition(groups, current_indent, indent)
            groups.map do |group|
              "#{current_indent}import_model #{Utils.camel_case(group[:ref_class])}"
            end.join("\n")
          end

          def render_choice_definition(choice, current_indent, indent)
            next_indent = (" " * indent) + current_indent
            choice_arr = ["#{current_indent}choice#{resolve_min_max_args(choice)} do"]
            choice.map do |key, value|
              next if key == :arguments

              case key
              when String
                choice_arr << render_elements_definition([{ key => value }], next_indent, indent)
              when :groups
                choice_arr << render_groups_definition(value, next_indent, indent)
              else
                binding.irb
              end
            end
            choice_arr << "#{current_indent}end"
            choice_arr.compact.join("\n")
          end

          def render_elements_definition(elements, current_indent, indent)
            elements.map do |element|
              element = element.values.first
              render_attribute_definition(element.element_name, element.type_name, element[:arguments], current_indent)
            end
          end

          def render_attributes_definition(attributes, current_indent, indent)
            attributes.compact.map do |attribute|
              render_attribute_definition(attribute.name, attribute.base_class, attribute[:arguments], current_indent)
            end
          end

          def render_attribute_definition(name, klass, arguments, current_indent)
            "#{current_indent}attribute :#{Utils.snake_case(name)}, :#{Utils.snake_case(normalized_class_name(klass))}#{resolve_occurs(arguments)}"
          end

          # START: RESOLVER METHODS
          def resolve_occurs(arguments)
            return unless arguments

            min_occurs = arguments[:min_occurs]
            max_occurs = arguments[:max_occurs]
            max_occurs = max_occurs.to_s&.match?(/[A-Za-z]+/) ? nil : max_occurs.to_i if max_occurs
            ", collection: #{max_occurs ? min_occurs.to_i..max_occurs : true}"
          end

          def resolve_min_max_args(mapping_hash)
            return unless mapping_hash&.key_exist?(:arguments)

            arguments = mapping_hash.arguments
            args_arr = []
            args_arr << "min: #{resolve_occur(mapping_hash.arguments.min_occurs)}" if arguments[:min_occurs]
            args_arr << "max: #{resolve_occur(mapping_hash.arguments.max_occurs)}" if arguments[:max_occurs]
            "(#{args_arr.join(', ')})"
          end

          def resolve_occur(occurs)
            occurs.to_s&.match?(/[A-Za-z]+/) ? "Float::INFINITY" : occurs.to_i
          end

          def resolve_required_files(content)
            @required_files = Set.new
            content.each do |key, value|
              case key
              when :sequence
                required_files_sequence(value)
              when :choice
                required_files_choice(value)
              when :group
                required_files_group(value)
              when :attributes
                required_files_attribute(value)
              when :attribute_groups
                value.each do |attribute_group|
                  required_files_attribute_groups(attribute_group)
                end
              when :complex_content
                required_files_complex_content(value)
              when :simple_content
                required_files_simple_content(value)
              end
            end
            @required_files
          end
          # END: RESOLVER METHODS

          # START: REQUIRED FILES LIST
          def required_files_simple_content(simple_content)
            simple_content.each do |key, value|
              case key
              when :extension_base
                # Do nothing.
              when :attributes
                required_files_attribute(value)
              when :extension
                required_files_extension(value)
              when :restriction
                required_files_restriction(value)
              end
            end
          end

          def required_files_complex_content(complex_content)
            complex_content.each do |key, value|
              case key
              when :extension
                required_files_extension(value)
              when :restriction
                required_files_restriction(value)
              end
            end
          end

          def required_files_extension(extension)
            extension.each do |key, value|
              case key
              when :attribute_group
                required_files_attribute_groups(value)
              when :attribute, :attributes
                required_files_attribute(value)
              when :extension_base
                # Do nothing.
              when :sequence
                required_files_sequence(value)
              when :choice
                required_files_choice(value)
              end
            end
          end

          def required_files_restriction(restriction)
            restriction.each do |key, value|
              case key
              when :base
                require_relative_file(Utils.snake_case(normalized_class_name(value)))
              end
            end
          end

          def required_files_attribute_groups(attr_groups)
            attr_groups.each do |key, value|
              case key
              when :ref_class
                required_files_attribute_groups(@attribute_groups[normalized_class_name(value)])
              when :attribute, :attributes
                required_files_attribute(value)
              end
            end
          end

          def required_files_attribute(attributes)
            attributes.each do |attribute|
              next if attribute[:ref_class]&.start_with?("xml") || attribute[:base_class]&.start_with?("xml")

              attribute = @attributes[normalized_class_name(attribute.ref_class)] if attribute.key_exist?(:ref_class)
              attr_class = normalized_class_name(attribute.base_class)
              next if DEFAULT_CLASSES.include?(attr_class)

              if attr_class == "decimal"
                @required_files << "require \"bigdecimal\""
              else
                require_relative_file(Utils.snake_case(attr_class))
              end
            end
          end

          def required_files_choice(choice)
            choice.each do |key, value|
              case key
              when String
                required_files_elements([value])
              when :group
                required_files_group(value)
              end
            end
          end

          def required_files_group(group)
            group.each do |key, value|
              case key
              when :sequence
                required_files_sequence(value)
              when :ref_class
                file_name = normalized_class_name(group[:ref_class])
                @required_files << "require_relative #{Utils.snake_case(file_name).inspect}"
              end
            end
          end

          def required_files_sequence(sequence)
            sequence.each do |key, value|
              case key
              when Hash
                if key.keys.one?(String)
                  required_files_elements(key.values)
                elsif key.key?(:groups)
                  required_files_group(key[:groups])
                end
              when :sequence
                required_files_sequences_array(value)
              when :choice
                required_groups_sequences_choice(value, called_method: key.to_s)
              end
            end
          end

          def required_files_sequences_array(sequences)
            sequences.each do |sequence|
              if sequence.keys.one?(String)
                required_files_elements(sequence.values)
              elsif sequence.key?(:sequence)
                required_files_sequence(sequence)
              elsif sequence.key?(:choice)
                required_files_choice(sequence[:choice])
              else
              end
            end
          end

          def required_groups_sequences_choice(array, called_method:)
            method_suffix = called_method.delete_suffix("s")
            array.each { |obj| public_send(:"required_files_#{method_suffix}", obj) }
          end

          def required_files_elements(elements)
            elements.flatten.each do |element|
              element = element.values.first if element.keys.one?(String)
              element_class = normalized_class_name(element.type_name)
              next if DEFAULT_CLASSES.include?(element_class)

              if element_class == "decimal"
                @required_files << "require \"bigdecimal\""
              else
                require_relative_file(Utils.snake_case(element_class))
              end
            end
          end
          # END: REQUIRED FILES LIST COMPILER METHODS

          def require_relative_file(file_name)
            @required_files << "require_relative \"#{file_name}\""
          end

          def normalized_class_name(class_name)
            class_name.split(":").last
          end
        end
      end
    end
  end
end
