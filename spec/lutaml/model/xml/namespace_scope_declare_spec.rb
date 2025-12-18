require "spec_helper"

RSpec.describe "namespace_scope Declaration Modes" do
  # Define test namespaces
  let(:app_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
      prefix_default "app"
    end
  end

  let(:vt_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
      prefix_default "vt"
    end
  end

  describe "declare: :auto (default)" do
    let(:model_class) do
      ns = app_namespace
      vt_ns = vt_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :template, :string

        xml do
          element "Properties"
          namespace ns
          namespace_scope [{ namespace: vt_ns, declare: :auto }]

          map_element "Template", to: :template
        end

        def self.name
          "Properties"
        end
      end
    end

    it "does NOT declare unused namespace" do
      instance = model_class.new(template: "Normal.dotm")
      xml = instance.to_xml

      # vt namespace should NOT be declared since it's not used
      expect(xml).not_to include("xmlns:vt=")
    end
  end

  describe "declare: :always" do
    let(:model_class) do
      ns = app_namespace
      vt_ns = vt_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :template, :string

        xml do
          element "Properties"
          namespace ns
          namespace_scope [{ namespace: vt_ns, declare: :always }]

          map_element "Template", to: :template
        end

        def self.name
          "Properties"
        end
      end
    end

    it "declares unused namespace" do
      instance = model_class.new(template: "Normal.dotm")
      xml = instance.to_xml

      # vt namespace SHOULD be declared even though not used
      expect(xml).to include('xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"')
    end
  end

  describe "per-namespace control with hash format" do
    let(:other_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://example.com/other"
        prefix_default "other"
      end
    end

    # TODO: This test is pending full Hash format implementation
    # The feature is designed but not yet implemented in validate_namespace_scope!
    xit "respects per-namespace declaration modes" do
      ns = app_namespace
      vt_ns = vt_namespace
      other_ns = other_namespace

      model_class = Class.new(Lutaml::Model::Serializable) do
        attribute :template, :string

        xml do
          element "Properties"
          namespace ns
          namespace_scope [
            { namespace: vt_ns, declare: :always },
            { namespace: other_ns, declare: :auto },
          ]

          map_element "Template", to: :template
        end

        def self.name
          "Properties"
        end
      end

      instance = model_class.new(template: "Normal.dotm")
      xml = instance.to_xml

      # vt namespace declared (always mode)
      expect(xml).to include("xmlns:vt=")

      # other namespace NOT declared (auto mode, not used)
      expect(xml).not_to include("xmlns:other=")
    end
  end

  describe "backward compatibility" do
    let(:model_class) do
      ns = app_namespace
      vt_ns = vt_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :template, :string

        xml do
          element "Properties"
          namespace ns
          namespace_scope [vt_ns] # No declare option - defaults to :auto

          map_element "Template", to: :template
        end

        def self.name
          "Properties"
        end
      end
    end

    it "defaults to :auto mode (backward compatible)" do
      instance = model_class.new(template: "Normal.dotm")
      xml = instance.to_xml

      # Should not declare unused namespace (auto mode default)
      expect(xml).not_to include("xmlns:vt=")
    end
  end

  describe "combined with prefix control" do
    let(:model_class) do
      ns = app_namespace
      vt_ns = vt_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :template, :string

        xml do
          element "Properties"
          namespace ns
          namespace_scope [{ namespace: vt_ns, declare: :always }]

          map_element "Template", to: :template
        end

        def self.name
          "Properties"
        end
      end
    end

    it "declares namespace_scope at root element" do
      instance = model_class.new(template: "Normal.dotm")
      xml = instance.to_xml

      # vt namespace should be declared at root
      expect(xml).to include('xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"')

      # app namespace declared as default (no prefix)
      expect(xml).to include('xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"')

      # Root element uses no prefix (default namespace)
      expect(xml).to match(/<Properties[>\s]/)
    end

    it "works with explicit prefix: true option" do
      instance = model_class.new(template: "Normal.dotm")
      xml = instance.to_xml(prefix: true)

      # Root namespace uses prefix
      expect(xml).to include("<app:Properties")
      expect(xml).to include("xmlns:app=")

      # vt namespace still declared
      expect(xml).to include("xmlns:vt=")
    end
  end
end
