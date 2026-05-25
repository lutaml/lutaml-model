module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD ComplexType -> Lutaml::Model::Serializable subclass.
        #
        # All rendering flow + hook defaults live in the base class
        # SerializableRenderer; only XSD-specific behavior is overridden
        # here.
        class ComplexType < Lutaml::Model::Schema::SerializableRenderer
          attr_accessor :id,
                        :name,
                        :mixed,
                        :instances,
                        :base_class,
                        :simple_content

          SERIALIZABLE_BASE_CLASS = "Lutaml::Model::Serializable".freeze

          SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE = ERB.new(<<~TMPL, trim_mode: "-")
            <%= @indent %>attribute :content, :<%= simple_content_type %><%= ", collection: true" if mixed && !simple_content? %>
            <%= simple_content.to_attributes(@indent) if simple_content? -%>
          TMPL

          def initialize(base_class: SERIALIZABLE_BASE_CLASS)
            super()
            @base_class = base_class
            @instances = []
            @module_namespace = nil
          end

          def <<(instance)
            return if instance.nil?

            @instances << instance
          end

          def simple_content?
            Utils.present?(@simple_content)
          end

          def required_files
            files = []
            # Only include external gem requires, not schema class requires
            # Schema class dependencies are handled via autoload registry
            unless @module_namespace
              files.concat(@instances.map(&:required_files).flatten.compact.uniq)
              files.concat(simple_content.required_files) if simple_content?
            end
            files
          end

          # --- SerializableRenderer overrides (only what differs) ---

          def setup_render_options(options)
            super
            namespace_uri = options[:namespace]
            @prefix = options[:prefix]

            return unless namespace_uri && XmlCompiler.namespace_classes

            ns_class = XmlCompiler.namespace_classes.values.find do |ns|
              ns.uri == namespace_uri
            end
            @namespace_class_name = ns_class&.class_name
          end

          def rendered_class_name
            Utils.camel_case(name)
          end

          def serializable_class_parent
            base_class_name
          end

          def serializable_class_required_files
            required_files.uniq.join("\n") + "\n"
          end

          def serializable_class_attributes
            attrs = @instances.flat_map { |i| i.to_attributes(@indent) }.join + "\n"
            attrs + simple_content_attribute.to_s
          end

          def xml_element_name
            name
          end

          def xml_namespace_line
            @namespace_class_name && "namespace #{@namespace_class_name}"
          end

          def xml_mixed_content?
            !!mixed
          end

          def xml_text_content?
            simple_content? || !!mixed
          end

          def xml_attribute_mappings
            @instances.flat_map { |i| i.to_xml_mapping(@extended_indent) }.join
          end

          def xml_extra_mappings
            simple_content? ? simple_content.to_xml_mapping(@extended_indent).to_s : ""
          end

          private

          def simple_content_type
            return "string" unless simple_content?

            Utils.snake_case(Utils.last_of_split(simple_content.base_class))
          end

          def simple_content_attribute
            SIMPLE_CONTENT_ATTRIBUTE_TEMPLATE.result(binding) if simple_content? || mixed
          end

          def base_class_name
            case base_class
            when SERIALIZABLE_BASE_CLASS
              SERIALIZABLE_BASE_CLASS
            else
              Utils.camel_case(Utils.last_of_split(base_class))
            end
          end
        end
      end
    end
  end
end
