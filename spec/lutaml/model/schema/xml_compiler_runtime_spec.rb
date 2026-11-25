# frozen_string_literal: true

require "spec_helper"
require "lutaml/model/schema"
require "tmpdir"

# Runtime XSD-to-classes compilation (#251): Schema.from_xml compiles a
# schema into generated Serializable classes, and with load_classes: the
# classes are available in-process for direct parsing and serialization —
# no generated files on disk.
RSpec.describe "runtime XSD class loading" do
  let(:xsd) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:complexType name="EntryType">
          <xs:sequence>
            <xs:element name="name" type="xs:string"/>
            <xs:element name="year" type="xs:integer"/>
          </xs:sequence>
          <xs:attribute name="id" type="xs:string" use="required"/>
        </xs:complexType>
        <xs:element name="entry" type="EntryType"/>
      </xs:schema>
    XSD
  end

  let(:instance_xml) do
    <<~XML
      <entry id="e1"><name>Alpha</name><year>2024</year></entry>
    XML
  end

  it "compiles a schema, loads the classes, and round-trips an instance" do
    Dir.mktmpdir do |dir|
      Lutaml::Model::Schema.from_xml(
        xsd, output_dir: File.join(dir, "runtime_pilot_models"),
             load_classes: true
      )

      doc = RuntimePilotModels::EntryType.from_xml(instance_xml)

      expect(doc.name).to eq("Alpha")
      expect(doc.year).to eq(2024)
      expect(doc.id).to eq("e1")

      expect(doc.to_xml).to include("<name>Alpha</name>")
      expect(doc.to_xml).to include("<year>2024</year>")
      expect(doc.to_xml).to include('id="e1"')
    end
  end

  # Anonymous (inline) complexTypes get CT_-prefixed internal names;
  # the generated classes must still (a) map skippable XSD built-ins
  # like xs:int to Lutaml primitives and (b) serialize the owning
  # element name, not the internal alias (#1014).
  describe "inline anonymous complexTypes" do
    let(:catalogue_xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   elementFormDefault="qualified">
          <xs:element name="catalogue">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="title" type="xs:string"/>
                <xs:element name="entry" maxOccurs="unbounded">
                  <xs:complexType>
                    <xs:sequence>
                      <xs:element name="name" type="xs:string"/>
                      <xs:element name="year" type="xs:int"/>
                    </xs:sequence>
                    <xs:attribute name="id" type="xs:string" use="required"/>
                  </xs:complexType>
                </xs:element>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
      XSD
    end

    let(:catalogue_xml) do
      <<~XML
        <catalogue>
          <title>Test</title>
          <entry id="e1"><name>Alpha</name><year>2024</year></entry>
          <entry id="e2"><name>Beta</name><year>2025</year></entry>
        </catalogue>
      XML
    end

    it "maps xs:int to :integer and parses the instance" do
      Dir.mktmpdir do |dir|
        Lutaml::Model::Schema.from_xml(
          catalogue_xsd, output_dir: File.join(dir, "anon_ct_models"),
                         load_classes: true
        )

        entry_class = AnonCtModels::CTEntry
        expect(entry_class.attributes[:year].type).to eq(
          Lutaml::Model::Type::Integer,
        )

        doc = AnonCtModels::CTCatalogue.from_xml(catalogue_xml)

        expect(doc.title).to eq("Test")
        expect(doc.entry.map(&:name)).to eq(["Alpha", "Beta"])
        expect(doc.entry.map(&:year)).to eq([2024, 2025])
        expect(doc.entry.map(&:id)).to eq(%w[e1 e2])
      end
    end

    it "serializes the owning element name, not the CT_ alias" do
      Dir.mktmpdir do |dir|
        Lutaml::Model::Schema.from_xml(
          catalogue_xsd, output_dir: File.join(dir, "anon_ct_models2"),
                         load_classes: true
        )

        entry = AnonCtModels2::CTEntry.from_xml(
          '<entry id="z9"><name>Gamma</name><year>1999</year></entry>',
        )

        expect(entry.name).to eq("Gamma")
        expect(entry.year).to eq(1999)
        expect(entry.id).to eq("z9")
        expect(entry.to_xml).to include('<entry id="z9">')
        expect(entry.to_xml).not_to include("CT_entry")
      end
    end
  end

  describe "builtin types and cardinality" do
    let(:xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ItemType">
            <xs:sequence>
              <xs:element name="title" type="xs:string"/>
              <xs:element name="issued" type="xs:gYearMonth" minOccurs="0"/>
              <xs:element name="note" type="xs:string" minOccurs="0"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="item" type="ItemType"/>
        </xs:schema>
      XSD
    end

    it "maps XSD builtins absent from the table (gYearMonth) and keeps
        optional singletons scalar" do
      sources = Lutaml::Model::Schema.from_xml(
        xsd, output_dir: "builtin_types_models", load_classes: true
      )

      model_name = sources.keys.find { |n| n.include?("Item") }
      doc = Object.const_get("BuiltinTypesModels::#{model_name}")

      parsed = doc.from_xml("<item><title>T1</title><issued>2026-11</issued></item>")
      expect(parsed.title).to eq("T1")
      expect(parsed.issued).to eq("2026-11")

      minimal = doc.from_xml("<item><title>T2</title></item>")
      expect(minimal.title).to eq("T2")
      # minOccurs=0, maxOccurs=1: scalar optional, not a collection
      expect(minimal.note).to be_nil
    end
  end

  describe "snake-spelled builtin union members" do
    let(:xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="dateOrYear">
            <xs:union memberTypes="xs:date xs:gYearMonth xs:gYear"/>
          </xs:simpleType>
          <xs:complexType name="StampType">
            <xs:sequence>
              <xs:element name="when" type="dateOrYear"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="stamp" type="StampType"/>
        </xs:schema>
      XSD
    end

    it "resolves union memberTypes against the table in either spelling" do
      sources = Lutaml::Model::Schema.from_xml(
        xsd, output_dir: "snake_builtin_models", load_classes: true
      )

      stamp_source = sources.values.find { |src| src.include?("StampType") }
      expect(stamp_source).not_to include("g_year_month")
    end
  end

  describe "g-date types" do
    it "registers :g_year_month so relaton-style models parse" do
      expect(Lutaml::Model::Type::GYearMonth.cast("2026-11")).to eq("2026-11")
      expect(Lutaml::Model::Type::TYPE_CODES).to include(:g_year_month)
      expect(Lutaml::Model::Type::TYPE_CODES[:g_year_month])
        .to eq("Lutaml::Model::Type::GYearMonth")
    end

    it "validates the lexical forms" do
      expect(Lutaml::Model::Type::GYearMonth.valid?("2026-11")).to be(true)
      expect(Lutaml::Model::Type::GYearMonth.valid?("2026-13")).to be(false)
      expect(Lutaml::Model::Type::GYear.valid?("0942")).to be(true)
      expect(Lutaml::Model::Type::GDay.valid?("---24")).to be(true)
      expect(Lutaml::Model::Type::GDay.valid?("24")).to be(false)
      expect(Lutaml::Model::Type::GMonthDay.valid?("--11-24")).to be(true)
      expect(Lutaml::Model::Type::GMonth.valid?("--11")).to be(true)
    end
  end

  # The union builder blanket-snakes member names, so every skippable
  # builtin spelling that a union can carry must resolve to a registered
  # type — #1190 covers the four the g-date work left out.
  describe "union members over the remaining skippable builtins" do
    {
      "xs:int" => ["int", "<rint><v>42</v></rint>", 42],
      "xs:QName" => ["qname", "<rqname><v>p:foo</v></rqname>", "p:foo"],
      "xs:IDREFS" => ["idrefs", "<ridrefs><v>a1 b2</v></ridrefs>", "a1 b2"],
      "xs:NMTOKENS" => ["nmtokens", "<rnmtokens><v>a1 b2</v></rnmtokens>",
                        "a1 b2"],
    }.each do |member, (suffix, xml, expected)|
      it "resolves a #{member} union member and parses an instance" do
        xsd = <<~XSD
          <?xml version="1.0" encoding="UTF-8"?>
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
            <xs:simpleType name="u#{suffix}">
              <xs:union memberTypes="#{member}"/>
            </xs:simpleType>
            <xs:complexType name="T#{suffix}">
              <xs:sequence>
                <xs:element name="v" type="u#{suffix}"/>
              </xs:sequence>
            </xs:complexType>
            <xs:element name="r#{suffix}" type="T#{suffix}"/>
          </xs:schema>
        XSD
        dir = "union_#{suffix}_models"
        Lutaml::Model::Schema.from_xml(
          xsd, output_dir: dir, load_classes: true
        )
        namespace = dir.split("_").map(&:capitalize).join

        parsed = Object.const_get("#{namespace}::T#{suffix}").from_xml(xml)

        expect(parsed.v).to eq(expected)
      end
    end
  end

  describe "builtin list spellings and aliases" do
    it "registers the union-facing symbols" do
      codes = Lutaml::Model::Type::TYPE_CODES

      expect(codes[:int]).to eq("Lutaml::Model::Type::Integer")
      expect(codes[:q_name]).to eq("Lutaml::Model::Type::QName")
      expect(codes[:idrefs]).to eq("Lutaml::Model::Type::IdRefs")
      expect(codes[:nmtokens]).to eq("Lutaml::Model::Type::NmTokens")
    end

    it "validates the IDREFS lexical form" do
      expect(Lutaml::Model::Type::IdRefs.valid?("a1")).to be(true)
      expect(Lutaml::Model::Type::IdRefs.valid?("a1 b2")).to be(true)
      expect(Lutaml::Model::Type::IdRefs.valid?("1a b2")).to be(false)
      expect(Lutaml::Model::Type::IdRefs.valid?("a1,b2")).to be(false)
      expect(Lutaml::Model::Type::IdRefs.valid?("")).to be(false)
    end

    it "validates the NMTOKENS lexical form" do
      expect(Lutaml::Model::Type::NmTokens.valid?("en-US")).to be(true)
      expect(Lutaml::Model::Type::NmTokens.valid?("en-US de-DE")).to be(true)
      expect(Lutaml::Model::Type::NmTokens.valid?("en US,fr")).to be(false)
      expect(Lutaml::Model::Type::NmTokens.valid?("")).to be(false)
    end
  end

  describe "register-isolated derivations (#1195)" do
    let(:base_xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ImportedThing">
            <xs:sequence>
              <xs:element name="label" type="xs:string"/>
            </xs:sequence>
          </xs:complexType>
        </xs:schema>
      XSD
    end

    let(:main_xsd) do
      <<~XSD
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:import schemaLocation="base.xsd"/>
          <xs:complexType name="MainDoc">
            <xs:sequence>
              <xs:element name="thing" type="ImportedThing"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="main" type="MainDoc"/>
        </xs:schema>
      XSD
    end

    let(:register_id) { :runtime_iso_reg }

    after do
      Lutaml::Model::GlobalRegister.unregister(register_id) if
        Lutaml::Model::GlobalRegister.lookup(register_id)
    end

    it "parses instances through imported-schema types from the " \
       "derivation's register, with the default register untouched" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "base.xsd"), base_xsd)
        File.write(File.join(dir, "main.xsd"), main_xsd)

        Lutaml::Model::Schema.from_xml(
          main_xsd,
          output_dir: File.join(dir, "reg_iso_models"),
          load_classes: true,
          module_namespace: "RegIsoRuntimeModels",
          register_id: register_id.to_s,
          location: File.join(dir, "main.xsd"),
        )

        parsed = RegIsoRuntimeModels::MainDoc.from_xml(
          "<main><thing><label>hello</label></thing></main>",
        )

        expect(parsed.thing.label).to eq("hello")
        expect(Lutaml::Model::Config.default_register).not_to eq(register_id)
      end
    end

    it "stamps the register through set_register_context, not " \
       "instance_variable_set" do
      entry = Lutaml::Model::Schema::CompiledOutput::Entry.new(
        "ImportedThing", nil, :model
      )
      source = Lutaml::Model::Schema::RegistryGenerator.generate(
        [entry], module_namespace: "ProbeRegNamespace",
                 register_id: register_id
      )

      expect(source).to include("set_register_context(:#{register_id})")
      expect(source).not_to include("instance_variable_set")
    end
  end
end
