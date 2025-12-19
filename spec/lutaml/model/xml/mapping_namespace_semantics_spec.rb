require "spec_helper"
require "lutaml/model"

RSpec.describe "Mapping-Level Namespace Semantics" do
  # Define test namespaces
  let(:parent_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/parent"
      prefix_default "par"
    end
  end

  let(:type_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://example.com/type"
      prefix_default "typ"
    end
  end

  # Define a custom type with namespace
  let(:namespaced_type) do
    ns = type_namespace
    Class.new(Lutaml::Model::Type::String) do
      xml_namespace ns
    end
  end

  describe "namespace: :inherit - Explicit Parent Inheritance" do
    context "when parent uses prefixed namespace" do
      let(:model_class) do
        par_ns = parent_namespace
        typed_str = namespaced_type

        Class.new(Lutaml::Model::Serializable) do
          attribute :value, typed_str # Type has own namespace

          xml do
            element "parent"
            namespace par_ns
            # Override type's namespace - use parent's instead
            map_element "child", to: :value, namespace: :inherit
          end

          def self.name
            "ExplicitInheritModel"
          end
        end
      end

      it "overrides type namespace and uses parent's namespace" do
        instance = model_class.new(value: "test")
        xml = instance.to_xml(prefix: true)

        # Parent triggers prefixed format due to :inherit child
        expect(xml).to include('xmlns:par="http://example.com/parent"')
        # Child uses parent's prefix, NOT type's prefix
        expect(xml).to include("<par:child>test</par:child>")
        # Type's namespace should NOT appear
        expect(xml).not_to include('xmlns:typ="http://example.com/type"')
      end

      it "round-trips correctly" do
        original = model_class.new(value: "roundtrip")
        xml = original.to_xml(prefix: true)
        parsed = model_class.from_xml(xml)

        expect(parsed.value).to eq("roundtrip")
        expect(parsed).to eq(original)
      end
    end

    context "when parent uses default namespace" do
      let(:model_class) do
        par_ns = parent_namespace
        typed_str = namespaced_type

        Class.new(Lutaml::Model::Serializable) do
          attribute :value, typed_str

          xml do
            element "parent"
            namespace par_ns
            map_element "child", to: :value, namespace: :inherit
          end

          def self.name
            "DefaultInheritModel"
          end
        end
      end

      it "creates qualified element inheriting parent namespace" do
        instance = model_class.new(value: "test")
        xml = instance.to_xml(prefix: true)

        # Parent is prefixed
        expect(xml).to include('xmlns:par="http://example.com/parent"')
        expect(xml).to include("<par:parent")

        # Child inherits parent namespace (native types always inherit)
        expect(xml).to include("<par:child>test</par:child>")
        expect(xml).not_to include("<typ:child")
      end
    end
  end

  describe "namespace: nil - Explicit No Namespace" do
    context "when parent has namespace" do
      # For this test, we need element_form_default: :qualified
      # so that children inherit parent's namespace qualification
      let(:qualified_parent_namespace) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/parent"
          prefix_default "par"
          element_form_default :qualified
        end
      end

      let(:model_class) do
        par_ns = qualified_parent_namespace

        Class.new(Lutaml::Model::Serializable) do
          attribute :namespaced_value, :string
          attribute :plain_value, :string

          xml do
            element "parent"
            namespace par_ns
            # This inherits parent namespace (qualified by schema setting)
            map_element "namespaced", to: :namespaced_value
            # This explicitly has NO namespace
            map_element "plain", to: :plain_value, namespace: nil
          end

          def self.name
            "ExplicitNoNamespace"
          end
        end
      end

      it "creates unqualified element despite namespaced parent" do
        instance = model_class.new(
          namespaced_value: "ns-value",
          plain_value: "plain-value",
        )
        xml = instance.to_xml(prefix: true)

        # Parent is prefixed
        expect(xml).to include('xmlns:par="http://example.com/parent"')
        expect(xml).to include("<par:parent")

        # namespaced inherits parent prefix (qualified by schema setting)
        expect(xml).to include("<par:namespaced>ns-value</par:namespaced>")

        # plain has explicit namespace: nil - no prefix
        expect(xml).to include("<plain>plain-value</plain>")
        expect(xml).not_to include("<par:plain>")
      end
    end

    context "when parent has default namespace" do
      let(:model_class) do
        par_ns = parent_namespace

        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            element "parent"
            namespace par_ns
            map_element "child", to: :value, namespace: nil
          end

          def self.name
            "NoNamespaceWithDefault"
          end
        end
      end

      it "creates unqualified element" do
        instance = model_class.new(value: "test")
        xml = instance.to_xml

        # Parent uses default namespace
        expect(xml).to include('xmlns="http://example.com/parent"')
        # W3C Rule: Child in blank namespace needs xmlns="" when parent uses default namespace
        expect(xml).to include('<child xmlns="">test</child>')
        expect(xml).not_to match(/<\w+:child>/)
      end
    end
  end

  describe "No namespace: option - Implicit Type-Level Behavior" do
    context "when attribute type has namespace" do
      let(:model_class) do
        par_ns = parent_namespace
        typed_str = namespaced_type

        Class.new(Lutaml::Model::Serializable) do
          attribute :value, typed_str

          xml do
            element "parent"
            namespace par_ns
            # No namespace: option - uses type's namespace
            map_element "child", to: :value
          end

          def self.name
            "TypeNamespaceModel"
          end
        end
      end

      it "uses type's namespace, not parent's" do
        instance = model_class.new(value: "test")
        xml = instance.to_xml(prefix: true)

        # Both namespaces declared
        expect(xml).to include('xmlns:par="http://example.com/parent"')
        expect(xml).to include('xmlns:typ="http://example.com/type"')

        # Parent uses parent namespace
        expect(xml).to include("<par:parent")
        # Child uses TYPE's namespace
        expect(xml).to include("<typ:child>test</typ:child>")
      end
    end

    context "when attribute type has no namespace" do
      let(:model_class) do
        par_ns = parent_namespace

        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string # Plain string - no type namespace

          xml do
            element "parent"
            namespace par_ns
            # No namespace: option with plain type
            map_element "child", to: :value
          end

          def self.name
            "ImplicitUnqualified"
          end
        end
      end

      it "creates unqualified element (elementFormDefault: unqualified)" do
        instance = model_class.new(value: "test")
        xml = instance.to_xml(prefix: true)

        # Parent is prefixed
        expect(xml).to include('xmlns:par="http://example.com/parent"')
        expect(xml).to include("<par:parent")
        # W3C Rule: Native types without explicit namespace are in blank namespace
        # They appear unqualified (no prefix, no xmlns)
        expect(xml).to include("<child>test</child>")
      end
    end
  end

  describe "Comparison of all three patterns" do
    let(:model_class) do
      par_ns = parent_namespace
      typed_str = namespaced_type

      Class.new(Lutaml::Model::Serializable) do
        attribute :inherit_value, typed_str
        attribute :explicit_nil, typed_str
        attribute :implicit_type, typed_str
        attribute :implicit_plain, :string

        xml do
          element "parent"
          namespace par_ns

          # Pattern 1: Explicit inherit - override type, use parent
          map_element "inherit", to: :inherit_value, namespace: :inherit

          # Pattern 2: Explicit nil - no namespace
          map_element "nil-ns", to: :explicit_nil, namespace: nil

          # Pattern 3a: Implicit with type namespace - use type
          map_element "typed", to: :implicit_type

          # Pattern 3b: Implicit without type namespace - unqualified
          map_element "plain", to: :implicit_plain
        end

        def self.name
          "ComparisonModel"
        end
      end
    end

    it "demonstrates all three namespace resolution patterns" do
      instance = model_class.new(
        inherit_value: "inherit",
        explicit_nil: "nil",
        implicit_type: "typed",
        implicit_plain: "plain",
      )
      xml = instance.to_xml(prefix: true)

      # Parent namespace declared (prefixed due to :inherit child)
      expect(xml).to include('xmlns:par="http://example.com/parent"')

      # Type namespace declared (for implicit_type only)
      expect(xml).to include('xmlns:typ="http://example.com/type"')

      # Pattern 1: :inherit uses parent namespace
      expect(xml).to include("<par:inherit>inherit</par:inherit>")

      # Pattern 2: nil has no namespace
      expect(xml).to include("<nil-ns>nil</nil-ns>")

      # Pattern 3a: Implicit uses type namespace
      expect(xml).to include("<typ:typed>typed</typ:typed>")

      # Pattern 3b: Native types without explicit namespace are in blank namespace
      # They appear unqualified when parent uses prefix format
      expect(xml).to include("<plain>plain</plain>")
    end
  end
end
