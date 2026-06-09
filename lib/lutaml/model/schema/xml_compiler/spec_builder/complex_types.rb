# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SpecBuilder
          # Builds Definitions::Model specs for XSD <complexType>, named
          # <group>, and <attributeGroup> nodes, plus the SimpleContent
          # sidecar.
          #
          # Reads from the parent SpecBuilder:
          #   - @parent.attribute_groups for ref resolution
          #   - @parent.group_types as the destination for anonymous
          #     named groups discovered while walking complexType bodies
          #   - @parent.namespace_class_name to stamp on built Models
          # Delegates leaf-member building (attribute/element/sequence/
          # choice) back to @parent.members for shared resolution rules.
          class ComplexTypes
            def initialize(parent)
              @parent = parent
            end

            # <xs:complexType> -> Definitions::Model.
            def build(complex_type)
              model = Definitions::Model.new(
                class_name: Utils.camel_case(complex_type.name),
                xml_root: Definitions::XmlRoot.new(kind: :element, name: complex_type.name),
                mixed: !!complex_type.mixed,
                namespace_class_name: @parent.namespace_class_name,
              )

              ElementOrder.resolved(complex_type).each do |element|
                add_child(model, element)
              end
              model
            end

            # <xs:group> at top level -> Definitions::Model with
            # module_wrappable: false. Used by both the registry walker
            # and by `add_group_to_model` when it discovers a named-but-
            # not-yet-registered anonymous group.
            def build_group(group)
              inner_members = []
              if (built = build_group_inner(group))
                inner_members << built
              end

              base_name = group.name || Utils.last_of_split(group.ref)
              Definitions::Model.new(
                class_name: Utils.camel_case(base_name),
                xml_root: Definitions::XmlRoot.new(kind: :type_name, name: base_name),
                members: inner_members,
                module_wrappable: false,
                lazy_register: true,
              )
            end

            # <xs:attributeGroup> -> Array of Definitions::Attribute. Top
            # level groups are registered for ref resolution; inline ones
            # are flattened directly into a Model's members.
            def build_attribute_group(attribute_group)
              ref = attribute_group.ref
              if ref && !attribute_group.name
                target = @parent.attribute_groups[Utils.last_of_split(ref)]
                return Array(target)
              end

              members = []
              ElementOrder.resolved(attribute_group).each do |item|
                case item
                when Lutaml::Xml::Schema::Xsd::Attribute
                  attr_spec = @parent.members_builder.build_attribute(item)
                  members << attr_spec if attr_spec
                when Lutaml::Xml::Schema::Xsd::AttributeGroup
                  members.concat(build_attribute_group(item))
                end
              end
              members
            end

            # <xs:simpleContent> -> Definitions::SimpleContent sidecar.
            def build_simple_content(simple_content)
              additional = []
              base_class = nil
              if simple_content.extension
                ext = simple_content.extension
                base_class = ext.base
                ElementOrder.resolved(ext).each do |item|
                  case item
                  when Lutaml::Xml::Schema::Xsd::Attribute
                    attr = @parent.members_builder.build_attribute(item)
                    additional << attr if attr
                  when Lutaml::Xml::Schema::Xsd::AttributeGroup
                    additional.concat(build_attribute_group(item))
                  end
                end
              elsif simple_content.restriction
                base_class = simple_content.restriction.base
              end

              Definitions::SimpleContent.new(
                base_class: base_class,
                additional_attributes: additional,
              )
            end

            private

            def add_child(model, element)
              case element
              when Lutaml::Xml::Schema::Xsd::Attribute
                attr = @parent.members_builder.build_attribute(element)
                model.members << attr if attr
              when Lutaml::Xml::Schema::Xsd::Sequence
                model.members << @parent.members_builder.build_sequence(element)
              when Lutaml::Xml::Schema::Xsd::Choice
                model.members << @parent.members_builder.build_choice(element)
              when Lutaml::Xml::Schema::Xsd::ComplexContent
                apply_complex_content(element, model)
              when Lutaml::Xml::Schema::Xsd::AttributeGroup
                model.members.concat(build_attribute_group(element))
              when Lutaml::Xml::Schema::Xsd::Group
                add_group_to_model(element, model)
              when Lutaml::Xml::Schema::Xsd::SimpleContent
                model.simple_content = build_simple_content(element)
              end
            end

            def apply_complex_content(content, model)
              model.mixed = true if content.mixed

              if (ext = content.extension)
                model.parent_class = qualified_class(ext.base)
                ElementOrder.resolved(ext).each { |c| add_child(model, c) }
              elsif (res = content.restriction)
                model.parent_class = qualified_class(res.base)
                ElementOrder.resolved(res).each do |c|
                  # XSD: restrictions on complex content inherit
                  # sequence/choice/group from base.
                  next if c.is_a?(Lutaml::Xml::Schema::Xsd::Sequence) ||
                    c.is_a?(Lutaml::Xml::Schema::Xsd::Choice) ||
                    c.is_a?(Lutaml::Xml::Schema::Xsd::Group)

                  add_child(model, c)
                end
              end
            end

            def qualified_class(raw)
              return "Lutaml::Model::Serializable" if raw.nil?

              Utils.camel_case(Utils.last_of_split(raw))
            end

            def add_group_to_model(group, model)
              # Anonymous group OR named-but-not-referenced group: unwrap
              # the inner sequence/choice inline into the model. (Matches
              # the old XmlCompiler::Group rendering, which only emitted
              # import_model_attributes/mappings when `ref` was set.)
              if group.ref.nil?
                add_anonymous_group_contents(group, model)
                if group.name && !@parent.group_types.key?(group.name)
                  @parent.group_types[group.name] = build_group(group)
                end
                return
              end

              model.members << Definitions::GroupImport.new(
                name: Utils.snake_case(Utils.last_of_split(group.ref)),
              )
            end

            def add_anonymous_group_contents(group, model)
              built = build_group_inner(group)
              model.members << built if built
            end

            def build_group_inner(group)
              inner = group.sequence || group.choice
              return nil unless inner

              case inner
              when Lutaml::Xml::Schema::Xsd::Sequence then @parent.members_builder.build_sequence(inner)
              when Lutaml::Xml::Schema::Xsd::Choice   then @parent.members_builder.build_choice(inner)
              end
            end
          end
        end
      end
    end
  end
end
