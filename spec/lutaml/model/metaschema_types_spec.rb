# frozen_string_literal: true

require "spec_helper"

# The NIST Metaschema simple data types (#107), per
# metaschema-datatypes.xsd and the sample values on
# pages.nist.gov/metaschema/specification/datatypes/.
RSpec.describe "NIST Metaschema simple data types" do
  describe Lutaml::Model::Type::EmailAddress do
    it "accepts addresses with an at-sign" do
      expect(described_class.valid?("mailbox@example.com")).to be(true)
      expect(described_class.cast("mailbox@example.com")).to eq("mailbox@example.com")
    end

    it "rejects strings without an at-sign" do
      expect(described_class.valid?("mailbox.example.com")).to be(false)
      expect(described_class.valid?("")).to be(false)
    end
  end

  describe Lutaml::Model::Type::Hostname do
    it "accepts non-empty trimmed strings" do
      expect(described_class.valid?("example.com")).to be(true)
      expect(described_class.valid?("localhost")).to be(true)
    end

    it "rejects empty and outer-whitespace values" do
      expect(described_class.valid?("")).to be(false)
      expect(described_class.valid?(" example.com ")).to be(false)
    end
  end

  describe Lutaml::Model::Type::IpV4Address do
    it "accepts dotted-quad addresses" do
      expect(described_class.valid?("192.168.0.1")).to be(true)
      expect(described_class.valid?("0.0.0.0")).to be(true)
      expect(described_class.valid?("255.255.255.255")).to be(true)
    end

    it "rejects out-of-range octets and malformed forms" do
      expect(described_class.valid?("256.0.0.1")).to be(false)
      expect(described_class.valid?("192.168.0")).to be(false)
      expect(described_class.valid?("192.168.0.1.5")).to be(false)
      expect(described_class.valid?("example.com")).to be(false)
    end
  end

  describe Lutaml::Model::Type::IpV6Address do
    it "accepts full and compressed forms" do
      expect(described_class.valid?("2001:db8:0:0:0:0:2:1")).to be(true)
      expect(described_class.valid?("2001:db8::2:1")).to be(true)
      expect(described_class.valid?("::1")).to be(true)
      expect(described_class.valid?("::")).to be(true)
      expect(described_class.valid?("fe80::1%eth0")).to be(true)
      expect(described_class.valid?("::ffff:192.168.0.1")).to be(true)
    end

    it "rejects malformed forms" do
      expect(described_class.valid?("2001:db8:::1")).to be(false)
      expect(described_class.valid?("192.168.0.1")).to be(false)
      expect(described_class.valid?("2001:db8:0:0:0:0:2")).to be(false)
    end
  end

  describe Lutaml::Model::Type::Token do
    it "accepts letters, digits, underscore and .-_ runs" do
      expect(described_class.valid?("simple")).to be(true)
      expect(described_class.valid?("_private.v2-final")).to be(true)
      expect(described_class.valid?("label3")).to be(true)
    end

    it "rejects leading digits, spaces, and empty values" do
      expect(described_class.valid?("3rd")).to be(false)
      expect(described_class.valid?("with space")).to be(false)
      expect(described_class.valid?("")).to be(false)
    end
  end

  describe Lutaml::Model::Type::UriReference do
    it "accepts relative and absolute references" do
      expect(described_class.valid?("#example")).to be(true)
      expect(described_class.valid?("relative/path")).to be(true)
      expect(described_class.valid?("https://example.com/x")).to be(true)
    end

    it "rejects empty and whitespace-padded values" do
      expect(described_class.valid?("")).to be(false)
      expect(described_class.valid?(" no ")).to be(false)
    end
  end

  describe Lutaml::Model::Type::Uuid do
    it "accepts version 4 and 5 UUIDs" do
      expect(described_class.valid?("a3bb189e-8bf9-4888-9912-ace4e6543002")).to be(true)
      expect(described_class.valid?("5c0da4c0-6d4d-5e21-b0cd-3a5f9b1c9d01")).to be(true)
    end

    it "rejects other versions and malformed values" do
      expect(described_class.valid?("a3bb189e-8bf9-1888-9912-ace4e6543002")).to be(false)
      expect(described_class.valid?("a3bb189e-8bf9-4888-9912ace4e6543002")).to be(false)
      expect(described_class.valid?("not-a-uuid")).to be(false)
    end
  end

  describe Lutaml::Model::Type::NonNegativeInteger do
    it "accepts zero and positive integers" do
      expect(described_class.valid?(0)).to be(true)
      expect(described_class.valid?("42")).to be(true)
      expect(described_class.cast("42")).to eq(42)
    end

    it "rejects negative values and non-integers" do
      expect(described_class.valid?(-1)).to be(false)
      expect(described_class.valid?("abc")).to be(false)
    end
  end

  describe Lutaml::Model::Type::PositiveInteger do
    it "accepts integers of one and above" do
      expect(described_class.valid?(1)).to be(true)
      expect(described_class.valid?("7")).to be(true)
    end

    it "rejects zero, negatives, and non-integers" do
      expect(described_class.valid?(0)).to be(false)
      expect(described_class.valid?(-3)).to be(false)
      expect(described_class.valid?("abc")).to be(false)
    end
  end

  describe Lutaml::Model::Type::DateWithTimezone do
    it "accepts dates with Z or an offset, per the page samples" do
      expect(described_class.valid?("2019-09-28Z")).to be(true)
      expect(described_class.valid?("2019-12-02-08:00")).to be(true)
    end

    it "rejects dates without a timezone" do
      expect(described_class.valid?("2019-09-28")).to be(false)
    end
  end

  describe Lutaml::Model::Type::DateTimeWithTimezone do
    it "accepts date-times with Z or an offset, per the page samples" do
      expect(described_class.valid?("2019-09-28T23:20:50.52Z")).to be(true)
      expect(described_class.valid?("2019-12-02T16:39:57-08:00")).to be(true)
      expect(described_class.valid?("2019-12-31T23:59:59Z")).to be(true)
    end

    it "rejects date-times without a timezone" do
      expect(described_class.valid?("2019-09-28T23:20:50.52")).to be(false)
    end
  end

  describe Lutaml::Model::Type::DayTimeDuration do
    it "accepts day and time durations, per the page samples" do
      expect(described_class.valid?("P1DT12H45M")).to be(true)
      expect(described_class.valid?("-PT3H")).to be(true)
      expect(described_class.valid?("PT0S")).to be(true)
      expect(described_class.valid?("P3D")).to be(true)
      expect(described_class.valid?("PT2M30.5S")).to be(true)
    end

    it "rejects year and month components" do
      expect(described_class.valid?("P1Y6M")).to be(false)
      expect(described_class.valid?("P1DT")).to be(false)
    end
  end

  describe Lutaml::Model::Type::YearMonthDuration do
    it "accepts year and month durations, per the page samples" do
      expect(described_class.valid?("P1Y6M")).to be(true)
      expect(described_class.valid?("-P9M")).to be(true)
      expect(described_class.valid?("P10M")).to be(true)
      expect(described_class.valid?("P2Y")).to be(true)
    end

    it "rejects time components and bare days" do
      expect(described_class.valid?("P1DT12H")).to be(false)
      expect(described_class.valid?("P3D")).to be(false)
    end
  end

  it "round-trips a metaschema-typed model through JSON" do
    stub_const("MetaNode", Class.new(Lutaml::Model::Serializable) do
      attribute :id, :uuid
      attribute :contact, :email_address
      attribute :address, :ip_v4_address
      attribute :retries, :non_negative_integer

      json do
        map "id", to: :id
        map "contact", to: :contact
        map "address", to: :address
        map "retries", to: :retries
      end
    end)

    model = MetaNode.from_json(
      '{"id":"a3bb189e-8bf9-4888-9912-ace4e6543002",' \
      '"contact":"ops@example.com","address":"10.0.0.7","retries":"3"}',
    )

    expect(model.id).to eq("a3bb189e-8bf9-4888-9912-ace4e6543002")
    expect(model.contact).to eq("ops@example.com")
    expect(model.address).to eq("10.0.0.7")
    expect(model.retries).to eq(3)
    expect(model.to_json).to eq(
      '{"id":"a3bb189e-8bf9-4888-9912-ace4e6543002",' \
      '"contact":"ops@example.com","address":"10.0.0.7","retries":3}',
    )
  end

  it "declares the metaschema XSD bases for schema generation" do
    expect(Lutaml::Model::Type::NonNegativeInteger.default_xsd_type)
      .to eq("xs:nonNegativeInteger")
    expect(Lutaml::Model::Type::PositiveInteger.default_xsd_type)
      .to eq("xs:positiveInteger")
    expect(Lutaml::Model::Type::DayTimeDuration.default_xsd_type)
      .to eq("xs:dayTimeDuration")
    expect(Lutaml::Model::Type::YearMonthDuration.default_xsd_type)
      .to eq("xs:yearMonthDuration")
    expect(Lutaml::Model::Type::Uuid.default_xsd_type).to eq("xs:string")
  end

  describe "wiring into validation and schema emission" do
    it "declares the patterns and bounds as Layer-2 facets" do
      expect(Lutaml::Model::Type::Uuid.facets[:pattern])
        .to include(Lutaml::Model::Type::Uuid::PATTERN)
      expect(Lutaml::Model::Type::NonNegativeInteger.facets[:min_inclusive])
        .to eq(0)
      expect(Lutaml::Model::Type::PositiveInteger.facets[:min_inclusive])
        .to eq(1)
    end

    it "validates metaschema-typed attributes through model validation" do
      stub_const("WiredNode", Class.new(Lutaml::Model::Serializable) do
        attribute :id, :uuid
        attribute :contact, :email_address
        attribute :retries, :positive_integer

        json do
          map "id", to: :id
          map "contact", to: :contact
          map "retries", to: :retries
        end
      end)

      good = WiredNode.new(id: "a3bb189e-8bf9-4888-9912-ace4e6543002",
                           contact: "ops@example.com", retries: 2)
      expect(good.validate).to be_empty

      bad = WiredNode.new(id: "not-a-uuid", contact: "no-at-sign", retries: 0)
      messages = bad.validate.map(&:message)

      expect(messages).to all(be_a(String))
      expect(messages.join("\n")).to include("id")
      expect(messages.join("\n")).to include("contact")
      expect(messages.join("\n")).to include("retries")
    end

    it "exports the metaschema restrictions in generated XSD" do
      stub_const("XsdNode", Class.new(Lutaml::Model::Serializable) do
        attribute :id, :uuid
        attribute :contact, :email_address
        attribute :retries, :positive_integer

        xml do
          element "node"
          map_attribute "id", to: :id
          map_element "contact", to: :contact
          map_element "retries", to: :retries
        end
      end)

      xsd = Lutaml::Model::Schema.to_xsd(XsdNode)

      expect(xsd).to include("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[45]")
      expect(xsd).to include(".+@.+")
      expect(xsd).to include('minInclusive value="1"')
    end

    it "keeps the metaschema pattern sources export-clean" do
      [Lutaml::Model::Type::IpV6Address,
       Lutaml::Model::Type::DayTimeDuration].each do |type|
        expect(type::PATTERN.source).not_to match(/\s/)
      end
    end
  end
end
