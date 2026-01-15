# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Type Namespace Examples" do
  describe "Contact with multiple namespaces using Type namespaces" do
    # Define namespace classes
    let(:contact_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/schemas/contact/v1"
        prefix_default "ct"
      end
    end

    let(:name_attribute_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/schemas/name-attributes/v1"
        prefix_default "name"
      end
    end

    # Define Type classes with namespaces (IMPLEMENTED syntax)
    let(:given_name_type) do
      ns = contact_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:surname_type) do
      ns = contact_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:name_prefix_type) do
      ns = name_attribute_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    # Define model classes
    let(:person_name_class) do
      given = given_name_type
      surname = surname_type
      prefix = name_prefix_type
      ns = contact_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :given_name, given
        attribute :surname, surname
        attribute :prefix, prefix
        attribute :suffix, :string

        xml do
          element "personName"
          namespace ns

          map_element "givenName", to: :given_name
          map_element "surname", to: :surname
          map_attribute "prefix", to: :prefix
          map_attribute "suffix", to: :suffix
        end

        def self.name
          "PersonName"
        end
      end
    end

    let(:contact_class) do
      person_name = person_name_class
      ns = contact_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :person_name, person_name

        xml do
          element "ContactInfo"
          namespace ns

          map_element "personName", to: :person_name
        end

        def self.name
          "Contact"
        end
      end
    end

    context "with default namespace and prefixed namespaces" do
      let(:xml) do
        <<~XML
          <ContactInfo xmlns="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1">
            <personName name:prefix="Dr." suffix="Jr.">
              <givenName>John</givenName>
              <surname>Doe</surname>
            </personName>
          </ContactInfo>
        XML
      end

      it "parses XML with default and prefixed namespaces" do
        contact = contact_class.from_xml(xml)

        expect(contact.person_name.given_name).to eq("John")
        expect(contact.person_name.surname).to eq("Doe")
        expect(contact.person_name.prefix).to eq("Dr.")
        expect(contact.person_name.suffix).to eq("Jr.")
      end

      it "preserves Type namespaces in round-trip" do
        original = contact_class.from_xml(xml)
        serialized = original.to_xml
        reparsed = contact_class.from_xml(serialized)

        expect(reparsed.person_name.given_name).to eq(original.person_name.given_name)
        expect(reparsed.person_name.surname).to eq(original.person_name.surname)
        expect(reparsed.person_name.prefix).to eq(original.person_name.prefix)
        expect(reparsed.person_name.suffix).to eq(original.person_name.suffix)

        expect(serialized).to include("xmlns")
        expect(serialized).to include("https://example.com/schemas/contact/v1")
        expect(serialized).to include("https://example.com/schemas/name-attributes/v1")
      end

      it "verifies object equality after round-trip" do
        original = contact_class.from_xml(xml)
        serialized = original.to_xml
        reparsed = contact_class.from_xml(serialized)

        expect(reparsed.person_name.given_name).to eq(original.person_name.given_name)
        expect(reparsed.person_name.surname).to eq(original.person_name.surname)
        expect(reparsed.person_name.prefix).to eq(original.person_name.prefix)
        expect(reparsed.person_name.suffix).to eq(original.person_name.suffix)
      end
    end

    context "parses XML regardless of prefixes used" do
      let(:xml_custom_prefix) do
        <<~XML
          <CT:ContactInfo xmlns:CT="https://example.com/schemas/contact/v1" xmlns:NA="https://example.com/schemas/name-attributes/v1">
            <CT:personName NA:prefix="Dr." suffix="Jr.">
              <CT:givenName>John</CT:givenName>
              <CT:surname>Doe</CT:surname>
            </CT:personName>
          </CT:ContactInfo>
        XML
      end

      it "parses XML with arbitrary prefixes" do
        contact = contact_class.from_xml(xml_custom_prefix)

        expect(contact.person_name.given_name).to eq("John")
        expect(contact.person_name.surname).to eq("Doe")
        expect(contact.person_name.prefix).to eq("Dr.")
        expect(contact.person_name.suffix).to eq("Jr.")
      end

      it "round-trips correctly with custom input prefixes" do
        contact = contact_class.from_xml(xml_custom_prefix)
        serialized = contact.to_xml
        reparsed = contact_class.from_xml(serialized)

        expect(reparsed.person_name.given_name).to eq(contact.person_name.given_name)
        expect(reparsed.person_name.prefix).to eq(contact.person_name.prefix)
      end
    end

    context "W3C attribute namespace compliance" do
      let(:xml) do
        <<~XML
          <ContactInfo xmlns="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1">
            <personName name:prefix="Dr." suffix="Jr.">
              <givenName>John</givenName>
              <surname>Doe</surname>
            </personName>
          </ContactInfo>
        XML
      end

      it "unprefixed attributes have no namespace per W3C" do
        contact = contact_class.from_xml(xml)
        serialized = contact.to_xml

        # suffix attribute should NOT have a prefix (W3C compliance)
        expect(serialized).to include('suffix="Jr."')
        expect(serialized).not_to match(/\w+:suffix=/)
      end

      it "Type-namespaced attributes are properly prefixed" do
        contact = contact_class.from_xml(xml)
        serialized = contact.to_xml

        # prefix attribute uses name: prefix from NamePrefixType
        expect(serialized).to match(/\w+:prefix="Dr."/)
      end
    end
  end

  describe "OOXML Core Properties with 4 namespaces using Type namespaces" do
    # Define namespace classes
    let(:cp_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
        prefix_default "cp"
      end
    end

    let(:dc_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://purl.org/dc/elements/1.1/"
        prefix_default "dc"
      end
    end

    let(:dcterms_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://purl.org/dc/terms/"
        prefix_default "dcterms"
      end
    end

    let(:xsi_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "http://www.w3.org/2001/XMLSchema-instance"
        prefix_default "xsi"
      end
    end

    # Define Type classes with namespaces (IMPLEMENTED syntax)
    let(:dc_title_type) do
      ns = dc_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:dc_creator_type) do
      ns = dc_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:cp_last_modified_by_type) do
      ns = cp_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:cp_revision_type) do
      ns = cp_namespace
      Class.new(Lutaml::Model::Type::Integer).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:xsi_type_type) do
      ns = xsi_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    # Define complex model types
    let(:dcterms_created_type) do
      xsi_type = xsi_type_type
      ns = dcterms_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :date_time
        attribute :type, xsi_type

        xml do
          element "created"
          namespace ns

          map_attribute "type", to: :type
          map_content to: :value
        end

        def self.name
          "DctermsCreatedType"
        end
      end
    end

    let(:dcterms_modified_type) do
      xsi_type = xsi_type_type
      ns = dcterms_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :value, :date_time
        attribute :type, xsi_type

        xml do
          element "modified"
          namespace ns

          map_attribute "type", to: :type
          map_content to: :value
        end

        def self.name
          "DctermsModifiedType"
        end
      end
    end

    # Define root model
    let(:core_properties_class) do
      title = dc_title_type
      creator = dc_creator_type
      last_mod = cp_last_modified_by_type
      revision = cp_revision_type
      created = dcterms_created_type
      modified = dcterms_modified_type
      ns = cp_namespace
      dc_ns = dc_namespace
      dcterms_ns = dcterms_namespace
      xsi_ns = xsi_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :title, title
        attribute :creator, creator
        attribute :last_modified_by, last_mod
        attribute :revision, revision
        attribute :created, created
        attribute :modified, modified

        xml do
          element "coreProperties"
          namespace ns

          # OOXML hoists dc and xsi namespaces to root
          # cp is root namespace (uses default format)
          # dcterms uses local default format (not hoisted)
          namespace_scope [dc_ns, xsi_ns]

          map_element "title", to: :title
          map_element "creator", to: :creator
          map_element "lastModifiedBy", to: :last_modified_by
          map_element "revision", to: :revision
          map_element "created", to: :created
          map_element "modified", to: :modified
        end

        def self.name
          "CoreProperties"
        end
      end
    end

    let(:xml) do
      <<~XML
        <cp:coreProperties
          xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:dcterms="http://purl.org/dc/terms/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>Untitled</dc:title>
          <dc:creator>Uniword</dc:creator>
          <cp:lastModifiedBy>Uniword</cp:lastModifiedBy>
          <cp:revision>1</cp:revision>
          <dcterms:created xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03Z</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03Z</dcterms:modified>
        </cp:coreProperties>
      XML
    end

    it "parses complex multi-namespace XML with Type namespaces" do
      props = core_properties_class.from_xml(xml)

      expect(props.title).to eq("Untitled")
      expect(props.creator).to eq("Uniword")
      expect(props.last_modified_by).to eq("Uniword")
      expect(props.revision).to eq(1)
      expect(props.created.value).to be_a(DateTime)
      expect(props.created.type).to eq("dcterms:W3CDTF")
      expect(props.modified.value).to be_a(DateTime)
      expect(props.modified.type).to eq("dcterms:W3CDTF")
    end

    it "preserves all Type namespaces in round-trip" do
      original = core_properties_class.from_xml(xml)
      serialized = original.to_xml
      reparsed = core_properties_class.from_xml(serialized)

      expect(reparsed.title).to eq(original.title)
      expect(reparsed.creator).to eq(original.creator)
      expect(reparsed.last_modified_by).to eq(original.last_modified_by)
      expect(reparsed.revision).to eq(original.revision)
      expect(reparsed.created.value.to_s).to eq(original.created.value.to_s)
      expect(reparsed.created.type).to eq(original.created.type)
      expect(reparsed.modified.value.to_s).to eq(original.modified.value.to_s)
      expect(reparsed.modified.type).to eq(original.modified.type)

      # Verify all 4 namespaces are declared
      expect(serialized).to include("xmlns")
      expect(serialized).to include("http://schemas.openxmlformats.org/package/2006/metadata/core-properties")
      expect(serialized).to include("http://purl.org/dc/elements/1.1/")
      expect(serialized).to include("http://purl.org/dc/terms/")
      expect(serialized).to include("http://www.w3.org/2001/XMLSchema-instance")
    end

    it "verifies Type namespace application to elements" do
      props = core_properties_class.from_xml(xml)
      serialized = props.to_xml

      # Debug: check if serialized is a string
      # puts "serialized.class = #{serialized.class}"
      # puts "serialized.length = #{serialized.length}"
      # puts "serialized.include?('<dcterms:created>') = #{serialized.include?('<dcterms:created>')}"
      # puts "serialized.include?('dcterms:created') = #{serialized.include?('dcterms:created')}"
      # puts "serialized.include?('&lt;dcterms:created&gt;') = #{serialized.include?('&lt;dcterms:created&gt;')}"
      # # Find position of dcterms:created
      # idx = serialized.index('dcterms:created')
      # if idx
      #   puts "Found 'dcterms:created' at index #{idx}"
      #   puts "Context: #{serialized[[idx-20, 0].max..idx+30]}"
      #   # Check characters before and after
      #   if idx > 0
      #     puts "Char before: '#{serialized[idx-1]}' (#{serialized[idx-1].ord})"
      #   end
      #   if idx + 15 < serialized.length
      #     puts "Char after 'dcterms:created': '#{serialized[idx+15]}' (#{serialized[idx+15].ord})"
      #   end
      # end

      # Elements with Type namespaces use their Type's namespace
      expect(serialized).to include("<dc:title>")
      expect(serialized).to include("<dc:creator>")
      # Elements with cp Type namespace use cp: prefix (matching input format)
      expect(serialized).to include("<cp:lastModifiedBy>")
      expect(serialized).to include("<cp:revision>")

      # dcterms elements use prefix format (hoisted to root)
      # Note: elements have attributes, so check for opening tag with space
      expect(serialized).to include("<dcterms:created ")
      expect(serialized).to include("</dcterms:created>")
      expect(serialized).to include("<dcterms:modified ")
      expect(serialized).to include("</dcterms:modified>")
      expect(serialized).to include('xsi:type="dcterms:W3CDTF"')

      # Verify dcterms namespace is declared at root (hoisted)
      expect(serialized).to match(/xmlns:dcterms="http:\/\/purl\.org\/dc\/terms\/"/)
    end

    it "verifies Type namespace application to attributes" do
      props = core_properties_class.from_xml(xml)
      serialized = props.to_xml

      # xsi:type attribute should use xsi: namespace from XsiTypeType
      expect(serialized).to match(/xsi:type="dcterms:W3CDTF"/)
    end

    it "handles multiple Type namespaces in single document" do
      props = core_properties_class.from_xml(xml)

      # Verify different types coexist properly
      expect(props.title).to eq("Untitled") # dc: namespace
      expect(props.revision).to eq(1) # cp: namespace
      expect(props.created.type).to eq("dcterms:W3CDTF") # xsi: namespace for attribute
    end
  end

  describe "Integration with existing namespace system" do
    let(:custom_namespace) do
      Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
        uri "https://example.com/custom"
        prefix_default "custom"
      end
    end

    let(:custom_type) do
      ns = custom_namespace
      Class.new(Lutaml::Model::Type::String).tap do |klass|
        klass.xml_namespace(ns)
      end
    end

    let(:model_class) do
      type = custom_type
      ns = custom_namespace

      Class.new(Lutaml::Model::Serializable) do
        attribute :value, type

        xml do
          element "example"
          namespace ns

          map_element "value", to: :value
        end

        def self.name
          "Example"
        end
      end
    end

    it "Type namespace integrates with model namespace" do
      model = model_class.new(value: "test")
      xml = model.to_xml

      # custom namespace is the default namespace (no prefix needed)
      expect(xml).to include('xmlns="https://example.com/custom"')
      expect(xml).to include("<value>test</value>")
    end

    it "maintains round-trip consistency" do
      model = model_class.new(value: "test")
      serialized = model.to_xml
      reparsed = model_class.from_xml(serialized)

      expect(reparsed.value).to eq(model.value)
    end
  end
end
