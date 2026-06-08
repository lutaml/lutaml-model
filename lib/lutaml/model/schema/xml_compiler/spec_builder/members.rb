# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class SpecBuilder
          # Builds the leaf member specs that live inside generated
          # classes: Attribute / Element (both surface as
          # Definitions::Attribute with different `kind:` values),
          # Sequence, Choice, GroupImport, plus the TypeRef wrapper.
          #
          # Holds @parent (SpecBuilder) so it can:
          #   - look up @parent.attributes / @parent.elements for refs
          #   - write anonymous simple/complex types into @parent's hashes
          #   - delegate complex-type building back to @parent for nested
          #     anonymous types
          class Members
            def initialize(parent)
              @parent = parent
            end

            # ----- Attributes ------------------------------------------------

            def build_attribute(attr)
              return resolve_attribute_ref(attr) if attr.ref && !attr.name

              Definitions::Attribute.new(
                name: Utils.snake_case(attr.name),
                type: build_type_ref(resolve_attribute_type(attr)),
                xml_name: attr.name,
                kind: :attribute,
                default: attr.default,
              )
            end

            def build_top_level_attribute(item, kind:)
              return item unless item.respond_to?(:name)

              type_str = top_level_type_str(item)
              Definitions::Attribute.new(
                name: Utils.snake_case(item.name.to_s),
                type: build_type_ref(type_str || "string"),
                xml_name: item.name.to_s,
                kind: kind,
              )
            end

            # ----- Elements --------------------------------------------------

            def build_element(element)
              return resolve_element_ref(element) if element.ref && !element.name

              Definitions::Attribute.new(
                name: Utils.snake_case(element.name),
                type: build_type_ref(resolve_element_type(element)),
                xml_name: element.name,
                kind: :element,
                collection: collection_from_occurs(element.min_occurs, element.max_occurs),
                default: element.default,
                render_default: !element.default.nil?,
                render_empty: element_required?(element.min_occurs),
              )
            end

            # ----- Sequence / Choice -----------------------------------------

            def build_sequence(sequence)
              members = @parent.resolved_element_order(sequence).filter_map do |item|
                next if item.is_a?(Lutaml::Xml::Schema::Xsd::Any)

                build_member(item)
              end
              Definitions::Sequence.new(members: members)
            end

            def build_choice(choice)
              alternatives = @parent.resolved_element_order(choice).filter_map { |item| build_member(item) }
              Definitions::Choice.new(
                alternatives: alternatives,
                header: choice_header(choice),
              )
            end

            # A `<xs:group ref="..."/>` appearing inside a sequence/choice
            # becomes an inline import directive. Anonymous in-place groups
            # (no name, no ref) are flattened by the complex-type walker
            # before they reach this method.
            def build_group_member(group)
              return nil if group.ref.nil?

              Definitions::GroupImport.new(
                name: Utils.snake_case(Utils.last_of_split(group.ref)),
              )
            end

            # ----- TypeRef ---------------------------------------------------

            def build_type_ref(raw_type)
              return Definitions::TypeRef.new(kind: :symbol, value: "string") if raw_type.nil?
              return Definitions::TypeRef.new(kind: :w3c, value: raw_type) if w3c_type?(raw_type)

              local = Utils.last_of_split(raw_type)
              Definitions::TypeRef.new(kind: :symbol, value: Utils.snake_case(local))
            end

            private

            def build_member(item)
              case item
              when Lutaml::Xml::Schema::Xsd::Sequence then build_sequence(item)
              when Lutaml::Xml::Schema::Xsd::Element  then build_element(item)
              when Lutaml::Xml::Schema::Xsd::Choice   then build_choice(item)
              when Lutaml::Xml::Schema::Xsd::Group    then build_group_member(item)
              end
            end

            def resolve_attribute_ref(attr)
              target = @parent.attributes[Utils.last_of_split(attr.ref)]
              return nil unless target

              Definitions::Attribute.new(
                name: target.name,
                type: target.type,
                xml_name: target.xml_name,
                kind: :attribute,
                default: target.default,
              )
            end

            def resolve_attribute_type(attr)
              return attr.type if attr.type

              register_anonymous_simple_type("ST_#{attr.name}", attr.simple_type)
            end

            def resolve_element_ref(element)
              target = @parent.elements[Utils.last_of_split(element.ref)]
              return nil unless target

              Definitions::Attribute.new(
                name: target.name,
                type: target.type,
                xml_name: target.xml_name,
                kind: :element,
                collection: collection_from_occurs(element.min_occurs, element.max_occurs),
                default: target.default,
                render_default: !target.default.nil?,
                render_empty: element_required?(element.min_occurs),
              )
            end

            def resolve_element_type(element)
              return element.type if element.type
              return register_anonymous_simple_type("ST_#{element.name}", element.simple_type) if element.simple_type
              return register_anonymous_complex_type("CT_#{element.name}", element.complex_type) if element.complex_type

              "string"
            end

            def top_level_type_str(item)
              return item.type if item.respond_to?(:type) && item.type
              return register_anonymous_simple_type("ST_#{item.name}", item.simple_type) if item.respond_to?(:simple_type) && item.simple_type

              register_anonymous_complex_type("CT_#{item.name}", item.complex_type) if item.respond_to?(:complex_type) && item.complex_type
            end

            def register_anonymous_simple_type(anon_name, anon_node)
              anon_node.name = anon_name
              @parent.simple_types[anon_name] = @parent.build_simple_type(anon_node)
              anon_name
            end

            def register_anonymous_complex_type(anon_name, anon_node)
              anon_node.name = anon_name
              @parent.complex_types[anon_name] = @parent.build_complex_type(anon_node)
              anon_name
            end

            def collection_from_occurs(min_occurs, max_occurs)
              return false if min_occurs.nil? && max_occurs.nil?

              min = min_occurs.nil? ? 1 : min_occurs.to_i
              max = case max_occurs
                    when "unbounded" then Float::INFINITY
                    when NilClass    then 1
                    else max_occurs.to_i
                    end
              return false if min == 1 && max == 1

              (min..max)
            end

            def element_required?(min_occurs)
              min_occurs.nil? || min_occurs.to_i >= 1
            end

            def choice_header(choice)
              min = choice.min_occurs.nil? ? 1 : choice.min_occurs.to_i
              max = case choice.max_occurs
                    when "unbounded" then "Float::INFINITY"
                    when NilClass    then 1
                    else choice.max_occurs.to_i
                    end
              "choice(min: #{min}, max: #{max})"
            end

            def w3c_type?(raw_type)
              raw_type.to_s.start_with?("Lutaml::Xml::W3c::")
            end
          end
        end
      end
    end
  end
end
