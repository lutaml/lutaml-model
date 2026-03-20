require "spec_helper"

require_relative "../../support/xml_mapping_namespaces"

RSpec.describe "Reusable XML Mapping Classes" do
  # rubocop:disable RSpec/BeforeAfterAll, RSpec/InstanceVariable
  # before(:all) is necessary to define classes once
  # instance variables are needed to reference classes in class body definitions
  before(:all) do
    @base_mapping_class = Class.new(Lutaml::Xml::Mapping) do
      xml do
        namespace XmiNamespace
        namespace_scope [XmiNamespace]
        map_element "Base", to: :base
      end
    end

    @parent_model_class = Class.new(Lutaml::Model::Serializable) do
      attribute :parent_attr, :string

      xml do
        element "Parent"
        namespace XmiNamespace
        namespace_scope [XmiNamespace]
        map_element "Parent", to: :parent_attr
      end
    end
  end

  describe "xml with a mapping class" do
    let(:model_class) do
      base_mapping = @base_mapping_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :base, :string

        xml base_mapping
      end
    end

    let(:child_model_class) do
      base_mapping = @base_mapping_class
      parent = @parent_model_class
      Class.new(parent) do
        attribute :child_attr, :string

        xml base_mapping do
          map_element "Child", to: :child_attr
        end
      end
    end

    it "inherits mappings from the referenced mapping class" do
      mapping = model_class.mappings[:xml]
      expect(mapping.mapping_elements_hash).to have_key("#{XmiNamespace.uri}:Base")
    end

    it "inherits namespace configuration from the mapping class" do
      mapping = model_class.mappings[:xml]
      expect(mapping.namespace_scope).to include(XmiNamespace)
    end

    context "when model has a parent with xml block" do
      it "inherits from both parent class mapping and referenced mapping class" do
        mapping = child_model_class.mappings[:xml]
        # Should have parent mapping
        expect(mapping.mapping_elements_hash).to have_key("#{XmiNamespace.uri}:Parent")
        # Should have mapping class mappings
        expect(mapping.mapping_elements_hash).to have_key("#{XmiNamespace.uri}:Base")
      end

      it "allows additional mappings via block" do
        mapping = child_model_class.mappings[:xml]
        expect(mapping.mapping_elements_hash).to have_key("#{XmiNamespace.uri}:Child")
      end
    end
  end

  describe "Lutaml::Xml::Mapping.xml class method" do
    it "creates and returns a mapping instance" do
      mapping_class = Class.new(Lutaml::Xml::Mapping) do
        xml do
          map_element "Test", to: :test
        end
      end

      expect(mapping_class.xml_mapping_instance).to be_a(Lutaml::Xml::Mapping)
    end

    it "evaluates the block in the mapping context" do
      mapping_class = Class.new(Lutaml::Xml::Mapping) do
        xml do
          map_element "Test", to: :test
        end
      end

      expect(mapping_class.xml_mapping_instance.mapping_elements_hash).to have_key("Test")
    end
  end

  describe "Listener collection methods" do
    let(:mapping_instance) do
      Class.new(Lutaml::Xml::Mapping) do
        xml do
          map_element "Element", to: :element
          map_attribute "attr", to: :attr
        end
      end.xml_mapping_instance
    end

    describe "#listeners_for" do
      it "returns listeners for a target" do
        listeners = mapping_instance.listeners_for("Element")
        expect(listeners).to be_a(Array)
      end
    end

    describe "#all_listeners" do
      it "returns all listeners" do
        expect(mapping_instance.all_listeners).to be_a(Array)
      end
    end

    describe "#omit_element" do
      it "removes all listeners for a target" do
        mapping_instance.omit_element("Element")
        expect(mapping_instance.listeners_for("Element")).to be_empty
      end
    end

    describe "#on_element with block" do
      it "adds a listener with a handler block" do
        custom_mapping = Class.new(Lutaml::Xml::Mapping) do
          xml do
            on_element "Custom", id: :custom_handler do |element, context|
              context[:custom] = element.text
            end
          end
        end.xml_mapping_instance

        listeners = custom_mapping.listeners_for("Custom")
        expect(listeners.size).to eq(1)
        expect(listeners.first.id).to eq(:custom_handler)
        expect(listeners.first.complex?).to be(true)
      end
    end
  end
  # rubocop:enable RSpec/BeforeAfterAll, RSpec/InstanceVariable
end
