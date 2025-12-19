require "spec_helper"

RSpec.describe "OOXML Extended Properties" do
  # Define OOXML namespaces
  let(:app_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
      prefix_default "app"
      element_form_default :qualified
    end
  end

  let(:vt_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"
      prefix_default "vt"
    end
  end

  # Model OOXML Properties
  let(:properties_class) do
    ns = app_namespace
    vt_ns = vt_namespace

    Class.new(Lutaml::Model::Serializable) do
      attribute :template, :string
      attribute :total_time, :integer
      attribute :pages, :integer
      attribute :words, :integer
      attribute :characters, :integer
      attribute :application, :string
      attribute :doc_security, :integer
      attribute :lines, :integer
      attribute :paragraphs, :integer
      attribute :scale_crop, :boolean
      attribute :company, :string
      attribute :links_up_to_date, :boolean
      attribute :characters_with_spaces, :integer
      attribute :shared_doc, :boolean
      attribute :hyperlinks_changed, :boolean
      attribute :app_version, :string

      xml do
        element "Properties"
        namespace ns

        # Solution 2: Force VtNamespace declaration even though unused
        namespace_scope [{ namespace: vt_ns, declare: :always }]

        map_element "Template", to: :template
        map_element "TotalTime", to: :total_time
        map_element "Pages", to: :pages
        map_element "Words", to: :words
        map_element "Characters", to: :characters
        map_element "Application", to: :application
        map_element "DocSecurity", to: :doc_security
        map_element "Lines", to: :lines
        map_element "Paragraphs", to: :paragraphs
        map_element "ScaleCrop", to: :scale_crop
        map_element "Company", to: :company
        map_element "LinksUpToDate", to: :links_up_to_date
        map_element "CharactersWithSpaces", to: :characters_with_spaces
        map_element "SharedDoc", to: :shared_doc
        map_element "HyperlinksChanged", to: :hyperlinks_changed
        map_element "AppVersion", to: :app_version
      end

      def self.name
        "Properties"
      end
    end
  end

  let(:sample_properties) do
    properties_class.new(
      template: "Normal.dotm",
      total_time: 0,
      pages: 1,
      words: 0,
      characters: 0,
      application: "Microsoft Office Word",
      doc_security: 0,
      lines: 0,
      paragraphs: 0,
      scale_crop: false,
      company: "",
      links_up_to_date: false,
      characters_with_spaces: 0,
      shared_doc: false,
      hyperlinks_changed: false,
      app_version: "16.0000",
    )
  end

  describe "Solution 1: Default namespace output" do
    it "outputs clean XML with default namespace (no prefix)" do
      xml = sample_properties.to_xml

      # Root element uses default namespace
      expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"')

      # Child elements have no prefix (inherit default namespace)
      expect(xml).to include("<Template>Normal.dotm</Template>")
      expect(xml).to include("<TotalTime>0</TotalTime>")
      expect(xml).to include("<Application>Microsoft Office Word</Application>")

      # No app: prefixes
      expect(xml).not_to include("app:Properties")
      expect(xml).not_to include("app:Template")
    end
  end

  describe "Solution 2: Forced unused namespace declaration" do
    it "declares vt namespace even though unused" do
      xml = sample_properties.to_xml

      # vt namespace declared at root even though not used
      expect(xml).to include('xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"')
    end
  end

  describe "Both solutions together" do
    it "produces the desired OOXML output format" do
      xml = sample_properties.to_xml

      # Should match desired output from default namespace implementation
      # 1. Default namespace (xmlns="...") for app namespace
      expect(xml).to include('<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"')

      # 2. Forced vt namespace declaration
      expect(xml).to include('xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"')

      # 3. No prefixes on elements
      expect(xml).to include("<Template>")
      expect(xml).to include("<Application>")

      # Full structure check
      expect(xml).to match(/<Properties.*xmlns="http:\/\/schemas.openxmlformats.org\/officeDocument\/2006\/extended-properties"/)
      expect(xml).to match(/xmlns:vt="http:\/\/schemas.openxmlformats.org\/officeDocument\/2006\/docPropsVTypes"/)
    end
  end

  describe "Backward compatible: prefix option" do
    it "supports prefix option to force prefixed output" do
      xml = sample_properties.to_xml(prefix: true)

      # Root uses app: prefix
      expect(xml).to include("<app:Properties")
      expect(xml).to include("xmlns:app=")

      # Child elements inherit parent namespace (native types always inherit)
      expect(xml).to include("<app:Template>")
      expect(xml).to include("<app:Application>")

      # Still declares vt namespace
      expect(xml).to include("xmlns:vt=")
    end
  end

  describe "Round-trip compatibility" do
    it "parses XML regardless of prefix format" do
      # Parse with default namespace
      xml_default = sample_properties.to_xml
      parsed_default = properties_class.from_xml(xml_default)

      # Parse with prefix
      xml_prefixed = sample_properties.to_xml(prefix: true)
      parsed_prefixed = properties_class.from_xml(xml_prefixed)

      # Both parse to same data
      expect(parsed_default.template).to eq("Normal.dotm")
      expect(parsed_prefixed.template).to eq("Normal.dotm")
      expect(parsed_default.application).to eq("Microsoft Office Word")
      expect(parsed_prefixed.application).to eq("Microsoft Office Word")
    end
  end
end
