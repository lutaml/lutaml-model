require "spec_helper"

RSpec.describe "XML namespace_scope feature" do
  # Define namespace classes
  let(:vcard_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "urn:ietf:params:xml:ns:vcard-4.0"
      prefix_default "vcard"
    end
  end

  let(:dcterms_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://purl.org/dc/terms/"
      prefix_default "dcterms"
    end
  end

  let(:dc_elements_namespace) do
    Class.new(Lutaml::Model::Xml::W3c::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
    end
  end

  # Define types with namespaces
  let(:vcard_version_type) do
    t = Class.new(Lutaml::Model::Type::String)
    t.xml_namespace(vcard_namespace)
    t
  end

  let(:vcard_fn_type) do
    t = Class.new(Lutaml::Model::Type::String)
    t.xml_namespace(vcard_namespace)
    t
  end

  let(:dc_title_type) do
    t = Class.new(Lutaml::Model::Type::String)
    t.xml_namespace(dc_elements_namespace)
    t
  end

  let(:dcterms_created_type) do
    t = Class.new(Lutaml::Model::Type::DateTime)
    t.xml_namespace(dcterms_namespace)
    t
  end

  # Define models
  let(:name_model) do
    vcard_ns = vcard_namespace
    Class.new(Lutaml::Model::Serializable) do
      attribute :given, :string
      attribute :family, :string
      attribute :suffix, :string
      attribute :prefix, :string

      xml do
        namespace vcard_ns
        element "n"
        map_element "given", to: :given
        map_element "family", to: :family
        map_element "suffix", to: :suffix
        map_element "prefix", to: :prefix
      end
    end
  end

  let(:address_model) do
    vcard_ns = vcard_namespace
    Class.new(Lutaml::Model::Serializable) do
      attribute :street_address, :string
      attribute :locality, :string
      attribute :region, :string
      attribute :postal_code, :string
      attribute :country_name, :string

      xml do
        namespace vcard_ns
        element "address"
        map_element "street-address", to: :street_address
        map_element "locality", to: :locality
        map_element "region", to: :region
        map_element "postal-code", to: :postal_code
        map_element "country-name", to: :country_name
      end
    end
  end

  let(:contact_model) do
    vcard_ns = vcard_namespace
    dc_title = dc_title_type
    vcard_fn = vcard_fn_type
    name_m = name_model
    address_m = address_model
    dcterms_created = dcterms_created_type

    Class.new(Lutaml::Model::Serializable) do
      attribute :title, dc_title
      attribute :fn, vcard_fn
      attribute :name, name_m
      attribute :email, :string
      attribute :email_type, :string
      attribute :tel, :string
      attribute :tel_type, :string
      attribute :address, address_m
      attribute :created, dcterms_created

      xml do
        namespace vcard_ns
        element "contact"
        map_element "title", to: :title
        map_element "fn", to: :fn
        map_element "n", to: :name
        map_element "email", to: :email
        map_attribute "type", to: :email_type
        map_element "tel", to: :tel
        map_attribute "type", to: :tel_type
        map_element "address", to: :address
        map_element "created", to: :created
      end
    end
  end

  describe "namespace_scope with all namespaces in scope" do
    let(:vcard_model) do
      vcard_ns = vcard_namespace
      dcterms_ns = dcterms_namespace
      dc_ns = dc_elements_namespace
      vcard_version = vcard_version_type
      contact_m = contact_model

      Class.new(Lutaml::Model::Serializable) do
        attribute :version, vcard_version
        attribute :contacts, contact_m, collection: true

        xml do
          namespace vcard_ns
          namespace_scope [vcard_ns, dcterms_ns, dc_ns]
          element "vCard"
          map_element "version", to: :version
          map_element "contacts", to: :contacts
        end
      end
    end

    let(:name_instance) do
      name_model.new(
        given: "John",
        family: "Doe",
        suffix: "Jr.",
        prefix: "Dr.",
      )
    end

    let(:address_instance) do
      address_model.new(
        street_address: "123 Main St",
        locality: "Anytown",
        region: "CA",
        postal_code: "12345",
        country_name: "USA",
      )
    end

    let(:contact_instance) do
      contact_model.new(
        title: "Contact: Dr. John Doe, Jr.",
        fn: "Dr. John Doe, Jr.",
        name: name_instance,
        email: "johndoe@example.com",
        email_type: "work",
        tel: "+1-555-555-5555",
        tel_type: "work",
        address: address_instance,
        created: DateTime.parse("2024-06-01T12:00:00Z"),
      )
    end

    let(:vcard_instance) do
      vcard_model.new(
        version: "4.0",
        contacts: [contact_instance],
      )
    end

    it "declares all namespaces on root element" do
      xml = vcard_instance.to_xml

      # Should have all three namespaces declared at root
      # Root namespace uses default xmlns format (not prefixed)
      expect(xml).to include('xmlns="urn:ietf:params:xml:ns:vcard-4.0"')
      # Other namespaces in scope use prefixed format
      expect(xml).to include('xmlns:dcterms="http://purl.org/dc/terms/"')
      expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')

      # Child elements should NOT redeclare these namespaces
      # Parse XML to check
      doc = Nokogiri::XML(xml)

      # Check root element has all namespaces
      root = doc.root
      expect(root.namespaces.values).to include("urn:ietf:params:xml:ns:vcard-4.0")
      expect(root.namespaces.values).to include("http://purl.org/dc/terms/")
      expect(root.namespaces.values).to include("http://purl.org/dc/elements/1.1/")

      # Check that child elements don't redeclare dc or dcterms
      # Note: contacts is the wrapper element containing contact data
      contacts = doc.at_xpath("//vcard:contacts",
                              "vcard" => "urn:ietf:params:xml:ns:vcard-4.0")
      expect(contacts).not_to be_nil

      # Title element should use dc prefix without redeclaring xmlns:dc
      title = contacts.at_xpath(".//dc:title", "dc" => "http://purl.org/dc/elements/1.1/")
      expect(title).not_to be_nil
      expect(title.text).to eq("Contact: Dr. John Doe, Jr.")
      # Should NOT have local xmlns:dc declaration
      expect(title.attributes.keys).not_to include("xmlns:dc")

      # Created element should use dcterms prefix without redeclaring xmlns:dcterms
      created = contacts.at_xpath(".//dcterms:created", "dcterms" => "http://purl.org/dc/terms/")
      expect(created).not_to be_nil
      # Should NOT have local xmlns:dcterms declaration
      expect(created.attributes.keys).not_to include("xmlns:dcterms")
    end

    it "roundtrips correctly with namespace_scope" do
      xml = vcard_instance.to_xml
      parsed = vcard_model.from_xml(xml)

      expect(parsed.version).to eq("4.0")
      expect(parsed.contacts.length).to eq(1)

      contact = parsed.contacts.first
      expect(contact.title).to eq("Contact: Dr. John Doe, Jr.")
      expect(contact.fn).to eq("Dr. John Doe, Jr.")
      expect(contact.name.given).to eq("John")
      expect(contact.name.family).to eq("Doe")
      expect(contact.created.to_s).to include("2024-06-01")
    end
  end

  describe "namespace_scope with limited namespaces" do
    let(:vcard_model_limited) do
      vcard_ns = vcard_namespace
      vcard_version = vcard_version_type
      contact_m = contact_model

      Class.new(Lutaml::Model::Serializable) do
        attribute :version, vcard_version
        attribute :contacts, contact_m, collection: true

        xml do
          namespace vcard_ns
          namespace_scope [vcard_ns] # Only vcard in scope
          element "vCard"
          map_element "version", to: :version
          map_element "contacts", to: :contacts
        end
      end
    end

    let(:name_instance) do
      name_model.new(
        given: "Robin",
        family: "Hoodwella",
      )
    end

    let(:address_instance) do
      address_model.new(
        street_address: "456 Oak St",
        locality: "Sometown",
        region: "TX",
        postal_code: "67890",
        country_name: "USA",
      )
    end

    let(:contact_instance) do
      contact_model.new(
        title: "Contact: Robin Hoodwella",
        fn: "Robin Hoodwella",
        name: name_instance,
        email: "robin.hoodwella@example.com",
        email_type: "home",
        tel: "+1-555-555-1234",
        tel_type: "home",
        address: address_instance,
        created: DateTime.parse("2024-06-02T15:30:00Z"),
      )
    end

    let(:vcard_instance) do
      vcard_model_limited.new(
        version: "4.0",
        contacts: [contact_instance],
      )
    end

    it "declares only vcard namespace at root, others locally" do
      xml = vcard_instance.to_xml

      # Find root element using XPath with registered namespace
      doc = Nokogiri::XML(xml)
      root = doc.at_xpath("/ns:vCard", "ns" => "urn:ietf:params:xml:ns:vcard-4.0")
      expect(root).not_to be_nil

      # Check that dc and dcterms are NOT declared at root level
      expect(root.namespace_definitions.map(&:prefix)).not_to include("dc")
      expect(root.namespace_definitions.map(&:prefix)).not_to include("dcterms")

      # But they ARE declared somewhere in the document (local declarations)
      dc_uri = "http://purl.org/dc/elements/1.1/"
      dcterms_uri = "http://purl.org/dc/terms/"

      # Count namespace declarations in the XML
      dc_declarations = xml.scan('xmlns:dc="').count
      dcterms_declarations = xml.scan('xmlns:dcterms="').count

      # Should have at least one declaration each (on first element that uses them)
      expect(dc_declarations).to be >= 1
      expect(dcterms_declarations).to be >= 1

      # Verify that elements using these namespaces exist and are accessible
      # Find contacts element (wrapper for contact data)
      contacts = doc.at_xpath("//ns:contacts", "ns" => "urn:ietf:params:xml:ns:vcard-4.0")
      expect(contacts).not_to be_nil

      # Child elements use these namespaces
      title = contacts.at_xpath(".//dc:title", "dc" => dc_uri)
      expect(title).not_to be_nil
      expect(title.text).to eq("Contact: Robin Hoodwella")

      # Created element uses dcterms
      created = contacts.at_xpath(".//dcterms:created",
                                  "dcterms" => dcterms_uri)
      expect(created).not_to be_nil
    end

    it "roundtrips correctly with limited namespace_scope" do
      xml = vcard_instance.to_xml
      parsed = vcard_model_limited.from_xml(xml)

      expect(parsed.version).to eq("4.0")
      expect(parsed.contacts.length).to eq(1)

      contact = parsed.contacts.first
      expect(contact.title).to eq("Contact: Robin Hoodwella")
      expect(contact.fn).to eq("Robin Hoodwella")
      expect(contact.name.given).to eq("Robin")
      expect(contact.name.family).to eq("Hoodwella")
      expect(contact.created.to_s).to include("2024-06-02")
    end
  end

  describe "namespace_scope validation" do
    it "raises error if namespace_scope is not an array" do
      vcard_ns = vcard_namespace

      expect do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            namespace_scope vcard_ns
          end
        end
      end.to raise_error(ArgumentError, /must be an Array/)
    end

    it "raises error if namespace_scope contains non-XmlNamespace classes" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            namespace_scope [String, Integer]
          end
        end
      end.to raise_error(ArgumentError,
                         /must contain only XmlNamespace classes/)
    end
  end
end
