require "spec_helper"
require "lutaml/model"

RSpec.describe "Type-level namespace round-trip tests" do
  describe "Contact example with 2 namespaces" do
    # Define namespace classes
    let(:contact_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "https://example.com/schemas/contact/v1"
        schema_location "https://example.com/schemas/contact/v1/contact.xsd"
        prefix_default "ct"
      end
    end

    let(:name_attribute_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "https://example.com/schemas/name-attributes/v1"
        schema_location "https://example.com/schemas/name-attributes/v1/name-attributes.xsd"
        prefix_default "name"
      end
    end

    # Define Type classes with namespaces
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

    # Define PersonName Model
    let(:person_name_class) do
      gn_type = given_name_type
      sn_type = surname_type
      np_type = name_prefix_type

      Class.new do
        include Lutaml::Model::Serialize

        attribute :given_name, gn_type
        attribute :surname, sn_type
        attribute :prefix, np_type
        attribute :suffix, :string

        xml do
          root "personName"
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

    # Define Contact Model
    let(:contact_class) do
      pn_class = person_name_class

      Class.new do
        include Lutaml::Model::Serialize

        attribute :person_name, pn_class

        xml do
          root "ContactInfo"
          map_element "personName", to: :person_name
        end

        def self.name
          "Contact"
        end
      end
    end

    # Test XML with ct namespace prefix
    let(:xml_with_default_ns) do
      <<~XML
        <ContactInfo>
          <personName xmlns:ct="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1" name:prefix="Dr." suffix="Jr.">
            <ct:givenName>John</ct:givenName>
            <ct:surname>Doe</ct:surname>
          </personName>
        </ContactInfo>
      XML
    end

    # Test XML with custom prefixes
    let(:xml_with_custom_prefixes) do
      <<~XML
        <ContactInfo>
          <personName xmlns:CT="https://example.com/schemas/contact/v1" xmlns:NA="https://example.com/schemas/name-attributes/v1" NA:prefix="Dr." suffix="Jr.">
            <CT:givenName>John</CT:givenName>
            <CT:surname>Doe</CT:surname>
          </personName>
        </ContactInfo>
      XML
    end

    it "parses XML with default namespace correct" do
      # NOTE: Parsing of Type-level namespaces not yet implemented
      instance = contact_class.from_xml(xml_with_default_ns)

      expect(instance.person_name.given_name).to eq("John")
      expect(instance.person_name.surname).to eq("Doe")
      expect(instance.person_name.prefix).to eq("Dr.")
      expect(instance.person_name.suffix).to eq("Jr.")
    end

    it "parses XML with custom prefixes correctly" do
      # NOTE: Parsing of Type-level namespaces not yet implemented
      instance = contact_class.from_xml(xml_with_custom_prefixes)

      expect(instance.person_name.given_name).to eq("John")
      expect(instance.person_name.surname).to eq("Doe")
      expect(instance.person_name.prefix).to eq("Dr.")
      expect(instance.person_name.suffix).to eq("Jr.")
    end

    it "preserves namespaces in round-trip from default namespace XML" do
      # NOTE: Parsing of Type-level namespaces not yet implemented
      original = contact_class.from_xml(xml_with_default_ns)
      serialized = original.to_xml

      expected_xml = <<~XML
        <ContactInfo>
          <personName xmlns:ct="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1" name:prefix="Dr." suffix="Jr.">
            <ct:givenName>John</ct:givenName>
            <ct:surname>Doe</ct:surname>
          </personName>
        </ContactInfo>
      XML

      expect(serialized).to be_xml_equivalent_to(expected_xml)

      # Parse again and verify equality
      reparsed = contact_class.from_xml(serialized)
      expect(reparsed.person_name.given_name).to eq(original.person_name.given_name)
      expect(reparsed.person_name.surname).to eq(original.person_name.surname)
      expect(reparsed.person_name.prefix).to eq(original.person_name.prefix)
      expect(reparsed.person_name.suffix).to eq(original.person_name.suffix)
    end

    it "preserves namespaces in round-trip from custom prefix XML" do
      # NOTE: Parsing of Type-level namespaces not yet implemented
      original = contact_class.from_xml(xml_with_custom_prefixes)
      serialized = original.to_xml

      expected_xml = <<~XML
        <ContactInfo>
          <personName xmlns:ct="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1" name:prefix="Dr." suffix="Jr.">
            <ct:givenName>John</ct:givenName>
            <ct:surname>Doe</ct:surname>
          </personName>
        </ContactInfo>
      XML

      expect(serialized).to be_xml_equivalent_to(expected_xml)

      # Parse again and verify equality
      reparsed = contact_class.from_xml(serialized)
      expect(reparsed.person_name.given_name).to eq(original.person_name.given_name)
      expect(reparsed.person_name.surname).to eq(original.person_name.surname)
      expect(reparsed.person_name.prefix).to eq(original.person_name.prefix)
      expect(reparsed.person_name.suffix).to eq(original.person_name.suffix)
    end

    it "applies Type namespace to elements correctly" do
      person_name = person_name_class.new(
        given_name: "Jane",
        surname: "Smith",
        prefix: "Mrs.",
        suffix: "Sr.",
      )
      contact = contact_class.new(person_name: person_name)

      xml = contact.to_xml

      expected_xml = <<~XML
        <ContactInfo>
          <personName xmlns:ct="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1" name:prefix="Mrs." suffix="Sr.">
            <ct:givenName>Jane</ct:givenName>
            <ct:surname>Smith</ct:surname>
          </personName>
        </ContactInfo>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "applies Type namespace to attributes correctly" do
      person_name = person_name_class.new(
        given_name: "Bob",
        surname: "Johnson",
        prefix: "Prof.",
        suffix: "PhD",
      )
      contact = contact_class.new(person_name: person_name)

      xml = contact.to_xml

      expected_xml = <<~XML
        <ContactInfo>
          <personName xmlns:ct="https://example.com/schemas/contact/v1" xmlns:name="https://example.com/schemas/name-attributes/v1" name:prefix="Prof." suffix="PhD">
            <ct:givenName>Bob</ct:givenName>
            <ct:surname>Johnson</ct:surname>
          </personName>
        </ContactInfo>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end
  end

  describe "OOXML Core Properties with 4 namespaces" do
    # Define namespace classes
    let(:cp_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
        prefix_default "cp"
      end
    end

    let(:dc_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://purl.org/dc/elements/1.1/"
        prefix_default "dc"
      end
    end

    let(:dcterms_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://purl.org/dc/terms/"
        prefix_default "dcterms"
      end
    end

    let(:xsi_namespace) do
      Class.new(Lutaml::Model::XmlNamespace) do
        uri "http://www.w3.org/2001/XMLSchema-instance"
        prefix_default "xsi"
      end
    end

    # Define Type classes with namespaces
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

    # Define DctermsCreated Model
    let(:dcterms_created_class) do
      xsi_type = xsi_type_type
      dcterms_ns = dcterms_namespace

      Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :date_time
        attribute :type, xsi_type

        xml do
          root "created"
          namespace dcterms_ns
          map_attribute "type", to: :type
          map_content to: :value
        end

        def self.name
          "DctermsCreated"
        end
      end
    end

    # Define DctermsModified Model
    let(:dcterms_modified_class) do
      xsi_type = xsi_type_type
      dcterms_ns = dcterms_namespace

      Class.new do
        include Lutaml::Model::Serialize

        attribute :value, :date_time
        attribute :type, xsi_type

        xml do
          root "modified"
          namespace dcterms_ns
          map_attribute "type", to: :type
          map_content to: :value
        end

        def self.name
          "DctermsModified"
        end
      end
    end

    # Define CoreProperties root model
    let(:core_properties_class) do
      dc_title = dc_title_type
      dc_creator = dc_creator_type
      cp_last_mod = cp_last_modified_by_type
      cp_rev = cp_revision_type
      dcterms_created = dcterms_created_class
      dcterms_modified = dcterms_modified_class

      Class.new do
        include Lutaml::Model::Serialize

        attribute :title, dc_title
        attribute :creator, dc_creator
        attribute :last_modified_by, cp_last_mod
        attribute :revision, cp_rev
        attribute :created, dcterms_created
        attribute :modified, dcterms_modified

        xml do
          root "coreProperties"
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

    # Test XML
    let(:ooxml_core_properties) do
      <<~XML
        <coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties">
          <dc:title>Untitled</dc:title>
          <dc:creator>Uniword</dc:creator>
          <cp:lastModifiedBy>Uniword</cp:lastModifiedBy>
          <cp:revision>1</cp:revision>
          <dcterms:created xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:created>
          <dcterms:modified xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:modified>
        </coreProperties>
      XML
    end

    it "parses complete OOXML Core Properties correctly" do
      # NOTE: Parsing of Type-level namespaces not yet implemented
      instance = core_properties_class.from_xml(ooxml_core_properties)

      expect(instance.title).to eq("Untitled")
      expect(instance.creator).to eq("Uniword")
      expect(instance.last_modified_by).to eq("Uniword")
      expect(instance.revision).to eq(1)
      expect(instance.created.value).to be_a(DateTime)
      expect(instance.created.type).to eq("dcterms:W3CDTF")
      expect(instance.modified.value).to be_a(DateTime)
      expect(instance.modified.type).to eq("dcterms:W3CDTF")
    end

    it "preserves all 4 namespaces in round-trip" do
      # NOTE: Parsing of Type-level namespaces not yet implemented
      original = core_properties_class.from_xml(ooxml_core_properties)
      serialized = original.to_xml

      expected_xml = <<~XML
        <coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties">
          <dc:title>Untitled</dc:title>
          <dc:creator>Uniword</dc:creator>
          <cp:lastModifiedBy>Uniword</cp:lastModifiedBy>
          <cp:revision>1</cp:revision>
          <dcterms:created xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:created>
          <dcterms:modified xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:modified>
        </coreProperties>
      XML

      expect(serialized).to be_xml_equivalent_to(expected_xml)

      # Parse again and verify equality
      reparsed = core_properties_class.from_xml(serialized)
      expect(reparsed.title).to eq(original.title)
      expect(reparsed.creator).to eq(original.creator)
      expect(reparsed.last_modified_by).to eq(original.last_modified_by)
      expect(reparsed.revision).to eq(original.revision)
      expect(reparsed.created.type).to eq(original.created.type)
      expect(reparsed.modified.type).to eq(original.modified.type)
    end

    it "applies correct element namespaces from Types" do
      created = dcterms_created_class.new(
        value: DateTime.parse("2025-11-13T17:11:03Z"),
        type: "dcterms:W3CDTF",
      )
      modified = dcterms_modified_class.new(
        value: DateTime.parse("2025-11-13T17:11:03Z"),
        type: "dcterms:W3CDTF",
      )

      instance = core_properties_class.new(
        title: "Test Document",
        creator: "Test Author",
        last_modified_by: "Test Modifier",
        revision: 1,
        created: created,
        modified: modified,
      )

      xml = instance.to_xml

      expected_xml = <<~XML
        <coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties">
          <dc:title>Test Document</dc:title>
          <dc:creator>Test Author</dc:creator>
          <cp:lastModifiedBy>Test Modifier</cp:lastModifiedBy>
          <cp:revision>1</cp:revision>
          <dcterms:created xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:created>
          <dcterms:modified xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:modified>
        </coreProperties>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "applies correct attribute namespace (xsi:type)" do
      created = dcterms_created_class.new(
        value: DateTime.parse("2025-11-13T17:11:03Z"),
        type: "dcterms:W3CDTF",
      )

      instance = core_properties_class.new(
        title: "Test",
        creator: "Author",
        last_modified_by: "Modifier",
        revision: 1,
        created: created,
        modified: created,
      )

      xml = instance.to_xml

      expected_xml = <<~XML
        <coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties">
          <dc:title>Test</dc:title>
          <dc:creator>Author</dc:creator>
          <cp:lastModifiedBy>Modifier</cp:lastModifiedBy>
          <cp:revision>1</cp:revision>
          <dcterms:created xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:created>
          <dcterms:modified xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:modified>
        </coreProperties>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)
    end

    it "handles complex nested structures correctly" do
      # NOTE: Parsing of Type-level namespaces not yet implemented - but verification at end requires parsing
      created = dcterms_created_class.new(
        value: DateTime.parse("2025-11-13T17:11:03Z"),
        type: "dcterms:W3CDTF",
      )
      modified = dcterms_modified_class.new(
        value: DateTime.parse("2025-11-14T10:20:30Z"),
        type: "dcterms:W3CDTF",
      )

      instance = core_properties_class.new(
        title: "Complex Document",
        creator: "Complex Author",
        last_modified_by: "Complex Modifier",
        revision: 5,
        created: created,
        modified: modified,
      )

      xml = instance.to_xml

      expected_xml = <<~XML
        <coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties">
          <dc:title>Complex Document</dc:title>
          <dc:creator>Complex Author</dc:creator>
          <cp:lastModifiedBy>Complex Modifier</cp:lastModifiedBy>
          <cp:revision>5</cp:revision>
          <dcterms:created xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-13T17:11:03+00:00</dcterms:created>
          <dcterms:modified xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="dcterms:W3CDTF">2025-11-14T10:20:30+00:00</dcterms:modified>
        </coreProperties>
      XML

      expect(xml).to be_xml_equivalent_to(expected_xml)

      # Verify round-trip preserves all values
      reparsed = core_properties_class.from_xml(xml)
      expect(reparsed.title).to eq(instance.title)
      expect(reparsed.creator).to eq(instance.creator)
      expect(reparsed.last_modified_by).to eq(instance.last_modified_by)
      expect(reparsed.revision).to eq(instance.revision)
      expect(reparsed.created.type).to eq(instance.created.type)
      expect(reparsed.modified.type).to eq(instance.modified.type)
      # DateTime comparison with tolerance
      expect((reparsed.created.value.to_time - instance.created.value.to_time).abs).to be < 1
      expect((reparsed.modified.value.to_time - instance.modified.value.to_time).abs).to be < 1
    end
  end
end
