# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Resolves the value-shape of an element or attribute container into a
        # Ruby type (Symbol for built-ins/registered types, or nil if the
        # container has structural content needing its own class).
        #
        # Patterns handled:
        #   <element><text/></element>                              -> :string
        #   <element><data type="X"/></element>                     -> mapped primitive
        #   <element><data ...><param ...>/></data></element>       -> anonymous SimpleType
        #   <element><choice><value>...</value></choice></element>  -> anonymous SimpleType (enum)
        #   <element><ref name="StFoo"/></element>                  -> :st_foo (if simple)
        #
        # When an anonymous SimpleType is needed, the resolver *builds* it
        # (pure) and asks the supplied `register_class` callback to register
        # it. Build and register are separate methods so unit testing can
        # exercise the pure logic without side effects.
        class ValueTypeResolver
          def initialize(defines, classes, compile_define:, register_class:)
            @defines = defines
            @classes = classes
            @compile_define = compile_define
            @register_class = register_class
          end

          # Returns the resolved type symbol, or nil if `container` needs
          # its own class. May register an anonymous SimpleType as a side
          # effect (delegated to the register_class callback).
          def resolve(container)
            return nil if RngHelpers.branching_structural?(container)

            type_from_inline_simple(container) || primitive_or_ref(container)
          end

          private

          # Returns a type symbol for any inline-restriction shape
          # (`<data><param>` or `<choice><value>`). Registers the generated
          # SimpleType via the callback as a side effect.
          def type_from_inline_simple(container)
            simple = build_anonymous_simple_type(container)
            return nil unless simple

            @register_class.call(simple)
            simple.type_symbol
          end

          # Pure: builds (but does NOT register) a SimpleType for inline
          # restrictions. Returns nil if no inline-restriction shape matches.
          def build_anonymous_simple_type(container)
            anonymous_from_data(container) || anonymous_from_enum_choice(container)
          end

          def anonymous_from_data(container)
            data = RngHelpers.single(container.respond_to?(:data) ? container.data : nil)
            return nil unless data && Array(data.param).any?

            base = RngCompiler::DATA_TYPE_MAP.fetch(
              data.type, RngCompiler::DEFAULT_DATA_TYPE
            )
            anonymous_simple_type(container, base, RngHelpers.restriction_from_data(data))
          end

          def anonymous_from_enum_choice(container)
            choice = RngHelpers.single(container.respond_to?(:choice) ? container.choice : nil)
            return nil unless choice && RngHelpers.pure_value_choice?(choice)

            anonymous_simple_type(container, :string, RngHelpers.restriction_from_values(choice.value))
          end

          def anonymous_simple_type(container, base, restriction)
            SimpleType.new(
              class_name: unique_class_name("#{Utils.camel_case(container.attr_name.to_s)}Type"),
              base_type: base,
              restriction: restriction,
            )
          end

          def primitive_or_ref(container)
            primitive = detect_primitive_type(container)
            return primitive if primitive

            ref_to_simple_type_symbol(container)
          end

          def ref_to_simple_type_symbol(container)
            ref = RngHelpers.single(container.respond_to?(:ref) ? container.ref : nil)
            return nil unless ref

            target = @defines[ref.name]
            return nil unless target

            target_class = @compile_define.call(target)
            return target_class.type_symbol if simple_type?(target_class)

            nil
          end

          def simple_type?(klass)
            klass.is_a?(SimpleType) || klass.is_a?(UnionType)
          end

          def detect_primitive_type(child)
            return nil unless child.respond_to?(:attr_name) || child.respond_to?(:data)
            return nil if RngHelpers.structural_content?(child)

            primitive_from_data(child) || primitive_from_text(child) || primitive_from_value(child)
          end

          def primitive_from_data(child)
            return nil unless child.respond_to?(:data) && child.data

            RngCompiler::DATA_TYPE_MAP.fetch(child.data.type, RngCompiler::DEFAULT_DATA_TYPE)
          end

          def primitive_from_text(child)
            :string if child.respond_to?(:text) && Utils.present?(child.text)
          end

          def primitive_from_value(child)
            # <element><choice><value>a</value>...</choice></element> falls
            # through to this path as :string with no constraint emitted.
            :string if child.respond_to?(:value) && Array(child.value).any?
          end

          def unique_class_name(base_name)
            return base_name unless @classes.key?(base_name)

            counter = 2
            counter += 1 while @classes.key?("#{base_name}#{counter}")
            "#{base_name}#{counter}"
          end
        end
      end
    end
  end
end
