require "spec_helper"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "lutaml/model/xml/oga_adapter"

# WARNING: This is a fictitious XML namespace example for vCard, vCard does not
# actually use XML in this way. This is solely for testing namespace_scope
# behavior.
#
RSpec.describe "namespace_scope with vCard" do
  # Define namespace classes
  let(:vcard_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "urn:ietf:params:xml:ns:vcard-4.0"
      prefix_default "vcard"
      element_form_default :qualified
    end
  end

  let(:dcterms_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://purl.org/dc/terms/"
      prefix_default "dcterms"
      element_form_default :qualified
    end
  end

  let(:dc_elements_namespace) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "http://purl.org/dc/elements/1.1/"
      prefix_default "dc"
      element_form_default :qualified
    end
  end

  # Define Type classes with namespaces
  let(:vcard_version_type) do
    ns = vcard_namespace
    Class.new(Lutaml::Model::Type::String).tap do |klass|
      klass.xml_namespace(ns)
    end
  end

  let(:dc_title_type) do
    ns = dc_elements_namespace
    Class.new(Lutaml::Model::Type::String).tap do |klass|
      klass.xml_namespace(ns)
    end
  end

  let(:dcterms_created_type) do
    ns = dcterms_namespace
    Class.new(Lutaml::Model::Type::DateTime).tap do |klass|
      klass.xml_namespace(ns)
    end
  end

  # Define nested Model classes
  let(:vcard_name_class) do
    v_ns = vcard_namespace

    Class.new(Lutaml::Model::Serializable) do
      attribute :given, :string
      attribute :family, :string
      attribute :prefix, :string
      attribute :suffix, :string

      xml do
        element "n"
        namespace v_ns
        map_element "given", to: :given
        map_element "family", to: :family
        map_element "prefix", to: :prefix
        map_element "suffix", to: :suffix
      end

      def self.name
        "VcardName"
      end
    end
  end

  let(:vcard_email_class) do
    v_ns = vcard_namespace

    Class.new(Lutaml::Model::Serializable) do
      attribute :value, :string
      attribute :type, :string

      xml do
        element "email"
        namespace v_ns
        map_attribute "type", to: :type
        map_content to: :value
      end

      def self.name
        "VcardEmail"
      end
    end
  end

  let(:vcard_tel_class) do
    v_ns = vcard_namespace

    Class.new(Lutaml::Model::Serializable) do
      attribute :value, :string
      attribute :type, :string

      xml do
        element "tel"
        namespace v_ns
        map_attribute "type", to: :type
        map_content to: :value
      end

      def self.name
        "VcardTel"
      end
    end
  end

  let(:vcard_address_class) do
    v_ns = vcard_namespace

    Class.new(Lutaml::Model::Serializable) do
      attribute :street_address, :string
      attribute :locality, :string
      attribute :region, :string
      attribute :postal_code, :string
      attribute :country_name, :string

      xml do
        element "address"
        namespace v_ns
        map_element "street-address", to: :street_address
        map_element "locality", to: :locality
        map_element "region", to: :region
        map_element "postal-code", to: :postal_code
        map_element "country-name", to: :country_name
      end

      def self.name
        "VcardAddress"
      end
    end
  end

  let(:vcard_contact_class) do
    v_ns = vcard_namespace
    dc_title = dc_title_type
    dcterms_created = dcterms_created_type
    name_class = vcard_name_class
    email_class = vcard_email_class
    tel_class = vcard_tel_class
    address_class = vcard_address_class

    Class.new(Lutaml::Model::Serializable) do
      attribute :title, dc_title
      attribute :fn, :string
      attribute :name, name_class
      attribute :email, email_class
      attribute :tel, tel_class
      attribute :address, address_class
      attribute :created, dcterms_created

      xml do
        element "contact"
        namespace v_ns
        map_element "title", to: :title
        map_element "fn", to: :fn
        map_element "n", to: :name
        map_element "email", to: :email
        map_element "tel", to: :tel
        map_element "address", to: :address
        map_element "created", to: :created
      end

      def self.name
        "VcardContact"
      end
    end
  end

  # Case 1: All namespaces in scope
  let(:vcard_class_with_full_scope) do
    v_ns = vcard_namespace
    dc_ns = dc_elements_namespace
    dcterms_ns = dcterms_namespace
    version_type = vcard_version_type
    contact_class = vcard_contact_class

    Class.new(Lutaml::Model::Serializable) do
      attribute :version, version_type
      attribute :contacts, contact_class, collection: true

      xml do
        element "vCard"
        namespace v_ns
        namespace_scope [v_ns, dc_ns, dcterms_ns]
        map_element "version", to: :version
        map_element "contact", to: :contacts
      end

      def self.name
        "Vcard"
      end
    end
  end

  # Case 2: Limited namespace scope (only vcard)
  let(:vcard_class_with_limited_scope) do
    v_ns = vcard_namespace
    version_type = vcard_version_type
    contact_class = vcard_contact_class

    Class.new(Lutaml::Model::Serializable) do
      attribute :version, version_type
      attribute :contacts, contact_class, collection: true

      xml do
        element "vCard"
        namespace v_ns
        namespace_scope [v_ns]
        map_element "version", to: :version
        map_element "contact", to: :contacts
      end

      def self.name
        "Vcard"
      end
    end
  end

  # Test data factory
  def create_test_vcard(vcard_class)
    name_class = vcard_name_class
    email_class = vcard_email_class
    tel_class = vcard_tel_class
    address_class = vcard_address_class
    contact_class = vcard_contact_class

    contact1 = contact_class.new(
      title: "Contact: Dr. John Doe, Jr.",
      fn: "Dr. John Doe, Jr.",
      name: name_class.new(
        given: "John",
        family: "Doe",
        prefix: "Dr.",
        suffix: "Jr.",
      ),
      email: email_class.new(value: "johndoe@example.com", type: "work"),
      tel: tel_class.new(value: "+1-555-555-5555", type: "work"),
      address: address_class.new(
        street_address: "123 Main St",
        locality: "Anytown",
        region: "CA",
        postal_code: "12345",
        country_name: "USA",
      ),
      created: DateTime.parse("2024-06-01T12:00:00Z"),
    )

    contact2 = contact_class.new(
      title: "Contact: Robin Hoodwella",
      fn: "Robin Hoodwella",
      name: name_class.new(
        given: "Robin",
        family: "Hoodwella",
      ),
      email: email_class.new(value: "robin.hoodwella@example.com",
                             type: "home"),
      tel: tel_class.new(value: "+1-555-555-1234", type: "home"),
      address: address_class.new(
        street_address: "456 Oak St",
        locality: "Sometown",
        region: "TX",
        postal_code: "67890",
        country_name: "USA",
      ),
      created: DateTime.parse("2024-06-02T15:30:00Z"),
    )

    vcard_class.new(
      version: "4.0",
      contacts: [contact1, contact2],
    )
  end

  shared_examples "namespace_scope behavior" do |adapter_class|
    around do |example|
      old_adapter = Lutaml::Model::Config.xml_adapter
      Lutaml::Model::Config.xml_adapter = adapter_class
      example.run
    ensure
      Lutaml::Model::Config.xml_adapter = old_adapter
    end

    describe "Case 1: All namespaces in scope" do
      let(:expected_xml_full_scope) do
        <<~XML
          <vCard xmlns="urn:ietf:params:xml:ns:vcard-4.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">
            <version>4.0</version>
            <contact>
              <dc:title>Contact: Dr. John Doe, Jr.</dc:title>
              <fn>Dr. John Doe, Jr.</fn>
              <n>
                <given>John</given>
                <family>Doe</family>
                <prefix>Dr.</prefix>
                <suffix>Jr.</suffix>
              </n>
              <email type="work">johndoe@example.com</email>
              <tel type="work">+1-555-555-5555</tel>
              <address>
                <street-address>123 Main St</street-address>
                <locality>Anytown</locality>
                <region>CA</region>
                <postal-code>12345</postal-code>
                <country-name>USA</country-name>
              </address>
              <dcterms:created>2024-06-01T12:00:00+00:00</dcterms:created>
            </contact>
            <contact>
              <dc:title>Contact: Robin Hoodwella</dc:title>
              <fn>Robin Hoodwella</fn>
              <n>
                <given>Robin</given>
                <family>Hoodwella</family>
              </n>
              <email type="home">robin.hoodwella@example.com</email>
              <tel type="home">+1-555-555-1234</tel>
              <address>
                <street-address>456 Oak St</street-address>
                <locality>Sometown</locality>
                <region>TX</region>
                <postal-code>67890</postal-code>
                <country-name>USA</country-name>
              </address>
              <dcterms:created>2024-06-02T15:30:00+00:00</dcterms:created>
            </contact>
          </vCard>
        XML
      end

      it "declares all namespaces at root element" do
        vcard = create_test_vcard(vcard_class_with_full_scope)
        xml = vcard.to_xml

        # Verify vcard uses default namespace, dc and dcterms are prefixed
        expect(xml).to include('xmlns="urn:ietf:params:xml:ns:vcard-4.0"')
        expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')
        expect(xml).to include('xmlns:dcterms="http://purl.org/dc/terms/"')

        # Verify no local namespace redeclarations on child elements
        # Extract just the contact section to check
        contact_section = xml.match(/<contact>.*?<\/contact>/m).to_s
        expect(contact_section).not_to include("xmlns:dc=")
        expect(contact_section).not_to include("xmlns:dcterms=")

        expect(xml).to be_xml_equivalent_to(expected_xml_full_scope)
      end

      it "uses prefixes without redeclaring xmlns on child elements" do
        vcard = create_test_vcard(vcard_class_with_full_scope)
        xml = vcard.to_xml

        # Count namespace declarations - should only be on root
        dc_declarations = xml.scan('xmlns:dc="').count
        dcterms_declarations = xml.scan('xmlns:dcterms="').count

        expect(dc_declarations).to eq(1),
                                   "dc namespace should be declared only once (at root)"
        expect(dcterms_declarations).to eq(1),
                                        "dcterms namespace should be declared only once (at root)"
      end

      it "preserves namespace scope in round-trip" do
        original = create_test_vcard(vcard_class_with_full_scope)
        xml = original.to_xml
        reparsed = vcard_class_with_full_scope.from_xml(xml)

        expect(reparsed.version).to eq(original.version)
        expect(reparsed.contacts.length).to eq(original.contacts.length)

        reparsed.contacts.each_with_index do |contact, idx|
          original_contact = original.contacts[idx]
          expect(contact.title).to eq(original_contact.title)
          expect(contact.fn).to eq(original_contact.fn)
          expect(contact.name.given).to eq(original_contact.name.given)
          expect(contact.name.family).to eq(original_contact.name.family)
          expect(contact.email.value).to eq(original_contact.email.value)
          expect(contact.tel.value).to eq(original_contact.tel.value)
          expect(contact.address.street_address).to eq(original_contact.address.street_address)
        end
      end

      it "serializes to compact XML format" do
        vcard = create_test_vcard(vcard_class_with_full_scope)
        xml = vcard.to_xml

        # Full scope should produce cleaner, more compact XML
        # No repeated namespace declarations
        expect(xml).to be_xml_equivalent_to(expected_xml_full_scope)
      end
    end

    describe "Case 2: Limited namespace scope" do
      let(:expected_xml_limited_scope) do
        <<~XML
          <vCard xmlns="urn:ietf:params:xml:ns:vcard-4.0">
            <version>4.0</version>
            <contact xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">
              <dc:title>Contact: Dr. John Doe, Jr.</dc:title>
              <fn>Dr. John Doe, Jr.</fn>
              <n>
                <given>John</given>
                <family>Doe</family>
                <prefix>Dr.</prefix>
                <suffix>Jr.</suffix>
              </n>
              <email type="work">johndoe@example.com</email>
              <tel type="work">+1-555-555-5555</tel>
              <address>
                <street-address>123 Main St</street-address>
                <locality>Anytown</locality>
                <region>CA</region>
                <postal-code>12345</postal-code>
                <country-name>USA</country-name>
              </address>
              <dcterms:created>2024-06-01T12:00:00+00:00</dcterms:created>
            </contact>
            <contact xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">
              <dc:title>Contact: Robin Hoodwella</dc:title>
              <fn>Robin Hoodwella</fn>
              <n>
                <given>Robin</given>
                <family>Hoodwella</family>
              </n>
              <email type="home">robin.hoodwella@example.com</email>
              <tel type="home">+1-555-555-1234</tel>
              <address>
                <street-address>456 Oak St</street-address>
                <locality>Sometown</locality>
                <region>TX</region>
                <postal-code>67890</postal-code>
                <country-name>USA</country-name>
              </address>
              <dcterms:created>2024-06-02T15:30:00+00:00</dcterms:created>
            </contact>
          </vCard>
        XML
      end

      it "declares only vcard namespace at root element" do
        vcard = create_test_vcard(vcard_class_with_limited_scope)
        xml = vcard.to_xml

        # Verify vcard namespace is declared as default namespace (xmlns="...")
        root_element = xml.match(/<vCard[^>]*>/).to_s
        expect(root_element).to include('xmlns="urn:ietf:params:xml:ns:vcard-4.0"')
        expect(root_element).not_to include("xmlns:dc=")
        expect(root_element).not_to include("xmlns:dcterms=")

        expect(xml).to be_xml_equivalent_to(expected_xml_limited_scope)
      end

      # W3C Rule: Namespaces can be declared at any ancestor element, not just
      # the individual elements that use them. The implementation optimizes by
      # declaring dc and dcterms at the lowest common ancestor (<contact>),
      # which is more efficient than declaring them on each individual element.
      it "declares dc and dcterms locally on elements using them" do
        vcard = create_test_vcard(vcard_class_with_limited_scope)
        xml = vcard.to_xml

        # Count namespace declarations - should be on contact container elements (one per contact)
        dc_declarations = xml.scan('xmlns:dc="').count
        dcterms_declarations = xml.scan('xmlns:dcterms="').count

        # W3C compliant: namespaces declared at container level (contact), not root
        expect(dc_declarations).to eq(2),
                                   "dc namespace should be declared twice (once per contact)"
        expect(dcterms_declarations).to eq(2),
                                        "dcterms namespace should be declared twice (once per contact)"

        # Verify that dc and dcterms namespaces are declared locally
        expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')
        expect(xml).to include('xmlns:dcterms="http://purl.org/dc/terms/"')
      end

      it "produces verbose XML with repeated declarations" do
        vcard = create_test_vcard(vcard_class_with_limited_scope)
        xml = vcard.to_xml

        # Limited scope produces more verbose XML with repeated namespace declarations
        expect(xml).to be_xml_equivalent_to(expected_xml_limited_scope)
      end

      it "preserves behavior in round-trip" do
        original = create_test_vcard(vcard_class_with_limited_scope)
        xml = original.to_xml
        reparsed = vcard_class_with_limited_scope.from_xml(xml)

        expect(reparsed.version).to eq(original.version)
        expect(reparsed.contacts.length).to eq(original.contacts.length)

        reparsed.contacts.each_with_index do |contact, idx|
          original_contact = original.contacts[idx]
          expect(contact.title).to eq(original_contact.title)
          expect(contact.fn).to eq(original_contact.fn)
          expect(contact.name.given).to eq(original_contact.name.given)
          expect(contact.name.family).to eq(original_contact.name.family)
          expect(contact.email.value).to eq(original_contact.email.value)
          expect(contact.tel.value).to eq(original_contact.tel.value)
          expect(contact.address.street_address).to eq(original_contact.address.street_address)
        end
      end
    end

    describe "Comparison between cases" do
      it "produces different XML serializations for same data" do
        vcard_full = create_test_vcard(vcard_class_with_full_scope)
        vcard_limited = create_test_vcard(vcard_class_with_limited_scope)

        xml_full = vcard_full.to_xml
        xml_limited = vcard_limited.to_xml

        # Different XML structure
        expect(xml_full).not_to eq(xml_limited)

        # But semantically equivalent data
        parsed_full = vcard_class_with_full_scope.from_xml(xml_full)
        parsed_limited = vcard_class_with_limited_scope.from_xml(xml_limited)

        expect(parsed_full.version).to eq(parsed_limited.version)
        expect(parsed_full.contacts.first.title).to eq(parsed_limited.contacts.first.title)
      end

      it "handles cross-parsing correctly" do
        # Create data with full scope
        vcard_full = create_test_vcard(vcard_class_with_full_scope)
        xml_full = vcard_full.to_xml

        # Parse with limited scope class (should still work - XML is semantically same)
        parsed_by_limited = vcard_class_with_limited_scope.from_xml(xml_full)
        expect(parsed_by_limited.version).to eq("4.0")
        expect(parsed_by_limited.contacts.first.title).to eq("Contact: Dr. John Doe, Jr.")

        # Create data with limited scope
        vcard_limited = create_test_vcard(vcard_class_with_limited_scope)
        xml_limited = vcard_limited.to_xml

        # Parse with full scope class (should also work)
        parsed_by_full = vcard_class_with_full_scope.from_xml(xml_limited)
        expect(parsed_by_full.version).to eq("4.0")
        expect(parsed_by_full.contacts.first.title).to eq("Contact: Dr. John Doe, Jr.")
      end
    end

    describe "Type namespace interaction with namespace_scope" do
      it "Type namespaces work correctly with full namespace_scope" do
        vcard = create_test_vcard(vcard_class_with_full_scope)
        xml = vcard.to_xml

        # Type-level namespaces should be respected
        # vcard uses default namespace (no prefix)
        expect(xml).to include("<version>")
        expect(xml).to include("<dc:title>")
        expect(xml).to include("<dcterms:created>")
      end

      it "Type namespaces work correctly with limited namespace_scope" do
        vcard = create_test_vcard(vcard_class_with_limited_scope)
        xml = vcard.to_xml

        # Type-level namespaces should be respected, with local declarations
        # vcard uses default namespace (no prefix)
        expect(xml).to include("<version>")
        expect(xml).to include("<dc:title")
        expect(xml).to include("<dcterms:created")
        expect(xml).to include('xmlns:dc="http://purl.org/dc/elements/1.1/"')
        expect(xml).to include('xmlns:dcterms="http://purl.org/dc/terms/"')
      end
    end
  end

  context "with Nokogiri adapter" do
    it_behaves_like "namespace_scope behavior", Lutaml::Model::Xml::NokogiriAdapter
  end

  context "with Oga adapter" do
    it_behaves_like "namespace_scope behavior", Lutaml::Model::Xml::OgaAdapter
  end
end
