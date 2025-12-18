require "spec_helper"
require_relative "../../support/xml_mapping_namespaces"

RSpec.describe "Namespace Backward Compatibility" do
  describe "xml-block level namespace" do
    context "with prefixed namespace" do
      let(:model_string_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "test"
            namespace "http://example.com/test", "ex"
            map_element "name", to: :name
          end
        end
      end

      let(:model_class_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string

          xml do
            element "test"
            namespace TestNamespace
            map_element "name", to: :name
          end
        end
      end

      it "string syntax produces same XML as class syntax" do
        instance_string = model_string_syntax.new(name: "Test Name")
        instance_class = model_class_syntax.new(name: "Test Name")

        xml_string = instance_string.to_xml
        xml_class = instance_class.to_xml

        expect(xml_string).to be_xml_equivalent_to(xml_class)
      end

      it "both syntaxes parse XML identically" do
        xml = '<ex:test xmlns:ex="http://example.com/test"><ex:name>Test Name</ex:name></ex:test>'

        parsed_string = model_string_syntax.from_xml(xml)
        parsed_class = model_class_syntax.from_xml(xml)

        expect(parsed_string.name).to eq(parsed_class.name)
      end
    end

    context "with default namespace" do
      let(:model_string_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "element"
            namespace "http://example.com/default"
            map_element "content", to: :content
          end
        end
      end

      let(:default_namespace_class) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/default"
          element_form_default :qualified
        end
      end

      let(:model_class_syntax) do
        ns_class = default_namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :content, :string

          xml do
            element "element"
            namespace ns_class
            map_element "content", to: :content
          end
        end
      end

      it "string syntax produces same XML as class syntax" do
        instance_string = model_string_syntax.new(content: "Test")
        instance_class = model_class_syntax.new(content: "Test")

        xml_string = instance_string.to_xml
        xml_class = instance_class.to_xml

        expect(xml_string).to be_xml_equivalent_to(xml_class)
      end
    end

    context "with nil prefix (explicit default namespace)" do
      let(:model_string_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            element "data"
            namespace "http://example.com/data", nil
            map_element "value", to: :value
          end
        end
      end

      let(:data_namespace_class) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/data"
          element_form_default :qualified
        end
      end

      let(:model_class_syntax) do
        ns_class = data_namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :value, :string

          xml do
            element "data"
            namespace ns_class, nil
            map_element "value", to: :value
          end
        end
      end

      it "string syntax produces same XML as class syntax" do
        instance_string = model_string_syntax.new(value: "Data")
        instance_class = model_class_syntax.new(value: "Data")

        xml_string = instance_string.to_xml
        xml_class = instance_class.to_xml

        expect(xml_string).to be_xml_equivalent_to(xml_class)
      end
    end
  end

  describe "mapping-level namespace" do
    context "with element namespace" do
      let(:model_string_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :description, :string

          xml do
            element "item"
            namespace "http://example.com/main", "main"
            map_element "title", to: :title
            map_element "desc", to: :description,
                                namespace: "http://example.com/desc"
          end
        end
      end

      let(:main_namespace_class) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/main"
          prefix_default "main"
          element_form_default :qualified
        end
      end

      let(:desc_namespace_class) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/desc"
          prefix_default "desc"
          element_form_default :qualified
        end
      end

      let(:model_class_syntax) do
        main_ns = main_namespace_class
        desc_ns = desc_namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :title, :string
          attribute :description, :string

          xml do
            element "item"
            namespace main_ns
            map_element "title", to: :title
            map_element "desc", to: :description, namespace: desc_ns
          end
        end
      end

      it "string syntax produces same XML as class syntax" do
        instance_string = model_string_syntax.new(
          title: "Title",
          description: "Description",
        )
        instance_class = model_class_syntax.new(
          title: "Title",
          description: "Description",
        )

        xml_string = instance_string.to_xml
        xml_class = instance_class.to_xml

        expect(xml_string).to be_xml_equivalent_to(xml_class)
      end
    end

    context "with attribute namespace" do
      let(:model_string_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :type, :string

          xml do
            element "element"
            map_attribute "id", to: :id
            map_attribute "type", to: :type,
                                  namespace: "http://www.w3.org/2001/XMLSchema-instance"
          end
        end
      end

      let(:xsi_namespace_class) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://www.w3.org/2001/XMLSchema-instance"
          prefix_default "xsi"
          element_form_default :qualified
        end
      end

      let(:model_class_syntax) do
        xsi_ns = xsi_namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :id, :string
          attribute :type, :string

          xml do
            element "element"
            map_attribute "id", to: :id
            map_attribute "type", to: :type, namespace: xsi_ns
          end
        end
      end

      it "string syntax produces same XML as class syntax" do
        instance_string = model_string_syntax.new(id: "123", type: "custom")
        instance_class = model_class_syntax.new(id: "123", type: "custom")

        xml_string = instance_string.to_xml
        xml_class = instance_class.to_xml

        expect(xml_string).to be_xml_equivalent_to(xml_class)
      end
    end

    context "with nil namespace (no namespace)" do
      let(:parent_namespace_class) do
        Class.new(Lutaml::Model::XmlNamespace) do
          uri "http://example.com/parent"
          prefix_default "p"
          element_form_default :qualified
        end
      end

      let(:model_string_syntax) do
        Class.new(Lutaml::Model::Serializable) do
          attribute :namespaced_child, :string
          attribute :no_namespace_child, :string

          xml do
            element "parent"
            namespace "http://example.com/parent", "p"
            map_element "withNs", to: :namespaced_child
            map_element "noNs", to: :no_namespace_child,
                                namespace: nil
          end
        end
      end

      let(:model_class_syntax) do
        parent_ns = parent_namespace_class
        Class.new(Lutaml::Model::Serializable) do
          attribute :namespaced_child, :string
          attribute :no_namespace_child, :string

          xml do
            element "parent"
            namespace parent_ns
            map_element "withNs", to: :namespaced_child
            map_element "noNs", to: :no_namespace_child,
                                namespace: nil
          end
        end
      end

      it "string syntax produces same XML as class syntax" do
        instance_string = model_string_syntax.new(
          namespaced_child: "NS",
          no_namespace_child: "NoN",
        )
        instance_class = model_class_syntax.new(
          namespaced_child: "NS",
          no_namespace_child: "NoN",
        )

        xml_string = instance_string.to_xml
        xml_class = instance_class.to_xml

        expect(xml_string).to be_xml_equivalent_to(xml_class)
      end
    end
  end

  describe "programmatic namespace method" do
    it "mapping.namespace() string API still works" do
      mapping = Lutaml::Model::Xml::Mapping.new
      mapping.root("element")
      mapping.namespace("http://example.com/test", "test")

      expect(mapping.namespace_uri).to eq("http://example.com/test")
      expect(mapping.namespace_prefix).to eq("test")
    end

    it "mapping.namespace() with XmlNamespace class works" do
      mapping = Lutaml::Model::Xml::Mapping.new
      mapping.root("element")
      mapping.namespace(TestNamespace)

      expect(mapping.namespace_uri).to eq("http://example.com/test")
      expect(mapping.namespace_prefix).to eq("test")
    end

    it "both approaches produce equivalent mappings" do
      mapping_string = Lutaml::Model::Xml::Mapping.new
      mapping_string.root("element")
      mapping_string.namespace("http://example.com/test", "test")

      mapping_class = Lutaml::Model::Xml::Mapping.new
      mapping_class.root("element")
      mapping_class.namespace(TestNamespace)

      expect(mapping_string.namespace_uri).to eq(mapping_class.namespace_uri)
      expect(mapping_string.namespace_prefix).to eq(mapping_class.namespace_prefix)
    end
  end
end
