# frozen_string_literal: true

module Lutaml
  module Lml
    class ModelCompiler
      # Applies declared LML serialization mappings
      # (xml / key_value wire names, namespaces) onto compiled classes.
      module SerializationMappings
        private

        # In-class `mapping <format> { … }` is the shortcut for a sibling
        # mapping targeting the enclosing class; hoist them so emission is
        # uniform.
        def hoist_class_serialization_mappings(doc)
          (Array(doc.classes) + Array(doc.data_types)).each do |klass_def|
            Array(klass_def.serialization_mappings).each do |mapping|
              mapping.target = klass_def.name.to_s
              @serialization_mappings << mapping
            end
          end
        end

        # Emit the lutaml-model mapping blocks declared in the LML source:
        #   mapping yaml { map "full-name", to: "name" }
        # becomes klass.yml do |m| m.map "full-name", to: :name end
        def apply_declared_mappings(compiled_klass, def_obj)
          return unless def_obj.is_a?(UmlClass) || def_obj.is_a?(DataType)

          def_obj.wire_mappings.to_a.group_by(&:format).each do |format, entries|
            next unless format && Lutaml::Model::FormatRegistry.registered?(format.to_sym)

            compiled_klass.public_send(format) do |mapping|
              entries.each { |entry| mapping.map(entry.wire, to: entry.to.to_sym) }
            end
          end
        end

        # Apply a lutaml-model XML mapping to each compiled class so they
        # support from_xml/to_xml. Runs after forward references are resolved
        # so all attributes (immediate + deferred) get element mappings.
        def apply_xml_mappings
          @compiled.each do |name, klass|
            next if @enum_names.include?(name)

            custom = serialization_mapping_for(name, 'xml')
            next apply_custom_xml_mapping(klass, custom) if custom

            apply_xml_mapping(klass, name)
          end
        end

        # Default XML mapping: every attribute an element, except those
        # declared `as :attribute`; an in-class `namespace "uri"` becomes
        # the class's XML namespace (issue #49).
        def apply_xml_mapping(klass, root_name)
          attr_names = klass.attributes.keys
          def_obj = @class_defs[root_name]
          roles = xml_roles_of(def_obj)
          ns_class = inline_namespace_class(def_obj)
          klass.xml do |mapping|
            mapping.element(root_name)
            mapping.namespace(ns_class) if ns_class
            attr_names.each do |attr_name|
              if roles[attr_name] == 'attribute'
                mapping.map_attribute(attr_name.to_s, to: attr_name)
              else
                mapping.map_element(attr_name.to_s, to: attr_name)
              end
            end
          end
        end

        def xml_roles_of(def_obj)
          Array(def_obj&.attributes).each_with_object({}) do |attr, roles|
            roles[attr.name.to_sym] = attr.xml_role if attr.xml_role
          end
        end

        def inline_namespace_class(def_obj)
          decl = def_obj.xml_namespace if def_obj.is_a?(UmlClass)
          return nil unless decl&.uri

          build_namespace_class("#{decl.uri}|#{decl.prefix}", decl.uri, decl.prefix.to_s)
        end

        # RS 3010 extension: key-value mapping blocks for the declared
        # formats (yaml/json/toml share lutaml-model's key_value model).

        # RS 3010 extension: key-value mapping blocks for the declared
        # formats (yaml/json/toml share lutaml-model's key_value model).
        def apply_key_value_mappings
          @compiled.each do |name, klass|
            next if @enum_names.include?(name)

            custom = serialization_mapping_for(name, 'key_value')
            apply_custom_key_value_mapping(klass, custom) if custom
          end
        end

        def serialization_mapping_for(target, format)
          @serialization_mappings.find do |m|
            m.target.to_s == target && serialization_format(m.format) == format
          end
        end

        def serialization_format(format)
          %w[yaml json toml].include?(format.to_s) ? 'key_value' : format.to_s
        end

        def apply_custom_xml_mapping(klass, mapping)
          check_namespace_ambiguity(mapping)
          ns_class = namespace_class_for(mapping.namespace_ref) if mapping.namespace_ref
          rule_ns = mapping.rules.select { |r| r.kind == 'namespace' }
                           .to_h { |r| [r.field, namespace_class_for(r.field)] }
          klass.xml do |m|
            m.element(mapping.element_name) if mapping.element_name
            m.namespace(ns_class) if ns_class
            m.mixed_content if mapping.mixed_content
            mapping.rules.each do |rule|
              case rule.kind
              when 'element' then m.map_element(rule.wire, to: rule.field.to_sym)
              when 'attribute' then m.map_attribute(rule.wire, to: rule.field.to_sym)
              when 'content' then m.map_content(to: rule.field.to_sym)
              when 'namespace' then m.namespace(rule_ns[rule.field])
              end
            end
          end
        end

        def apply_custom_key_value_mapping(klass, mapping)
          formats = mapping.format.to_s == 'key_value' ? %w[yaml json toml] : [mapping.format.to_s]
          klass.instance_eval do
            formats.each do |format|
              public_send(format) do |m|
                mapping.rules.each do |rule|
                  case rule.kind
                  when 'map' then m.map(rule.wire, to: rule.field.to_sym)
                  when 'key' then m.map_key(to_instance: rule.field.to_sym)
                  when 'value'
                    if rule.mode == 'as_attribute'
                      m.map_value(as_attribute: rule.field.to_sym)
                    else
                      m.map_value(to_instance: rule.field.to_sym)
                    end
                  end
                end
              end
            end
          end
        end

        def check_namespace_ambiguity(mapping)
          return unless mapping.format.to_s == 'xml'
          return if mapping.namespace_ref || @declared_namespaces.length < 2

          raise ArgumentError,
                "mapping #{mapping.format} #{mapping.target}: ambiguous default " \
                "namespace — #{@declared_namespaces.length} namespaces in scope " \
                "(#{@declared_namespaces.map(&:name).join(', ')}); declare one with " \
                "'namespace <name>'"
        end

        def namespace_class_for(ref)
          return nil if ref.nil?

          require 'lutaml/xml/namespace' unless defined?(Lutaml::Xml::Namespace)

          ns_class = @namespace_classes[ref]
          return ns_class if ns_class

          declared = @declared_namespaces.find { |ns| ns.name.to_s == ref }
          raise ArgumentError, "unknown namespace '#{ref}'" unless declared

          build_namespace_class(ref, declared.uri, declared.prefix.to_s)
        end

        def build_namespace_class(key, uri, prefix)
          require 'lutaml/xml/namespace' unless defined?(Lutaml::Xml::Namespace)

          @namespace_classes[key] ||= Class.new(Lutaml::Xml::Namespace).tap do |ns_class|
            ns_class.define_singleton_method(:uri) { uri }
            ns_class.define_singleton_method(:prefix_default) { prefix }
          end
        end
      end
    end
  end
end
