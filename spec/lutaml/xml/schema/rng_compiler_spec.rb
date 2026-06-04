require "rng"
require "spec_helper"
require "lutaml/model/schema"
require "tmpdir"

RSpec.describe Lutaml::Model::Schema::RngCompiler do
  # Reset :default context before each test so generated classes from one
  # context don't leak into another. Matches XSD compiler spec setup.
  before do
    default_ctx = Lutaml::Model::GlobalContext.context(:default)
    if default_ctx
      default_ctx.registry.clear
      Lutaml::Model::Type.register_builtin_types_in(default_ctx.registry)
    end
  end

  describe ".to_models" do
    context "with the address_book RNG schema (start element + zeroOrMore + ref + text + fragment define)" do
      before do
        stub_const("RngAddressBookSpec", Module.new)
        described_class.to_models(
          schema,
          output_dir: dir,
          create_files: true,
          module_namespace: "RngAddressBookSpec",
        )
        require File.join(dir, "rngaddressbookspec_registry.rb")
        RngAddressBookSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:schema) { File.read("spec/fixtures/xml/schema/rng/address_book.rng") }

      let(:valid_xml) do
        <<~XML
          <addressBook>
            <card>
              <name>Alice</name>
              <email>alice@example.com</email>
            </card>
            <card>
              <name>Bob</name>
              <email>bob@example.com</email>
            </card>
          </addressBook>
        XML
      end

      it "writes per-class files and a central registry" do
        module_dir = File.join(dir, "rngaddressbookspec")
        expect(File).to exist(File.join(dir, "rngaddressbookspec_registry.rb"))
        expect(File).to exist(File.join(module_dir, "address_book.rb"))
        expect(File).to exist(File.join(module_dir, "card.rb"))
        expect(File).to exist(File.join(module_dir, "card_content.rb"))
      end

      it "loads the AddressBook constant after register_all" do
        expect(defined?(RngAddressBookSpec::AddressBook)).to eq("constant")
        expect(defined?(RngAddressBookSpec::Card)).to eq("constant")
        expect(defined?(RngAddressBookSpec::CardContent)).to eq("constant")
      end

      it "round-trips a valid XML document through the generated classes" do
        book = RngAddressBookSpec::AddressBook.from_xml(valid_xml)
        expect(book.card.size).to eq(2)
        expect(book.card[0].name).to eq("Alice")
        expect(book.card[1].email).to eq("bob@example.com")
        expect(book.to_xml).to be_xml_equivalent_to(valid_xml)
      end
    end

    context "with the book RNG schema (attribute + optional + oneOrMore + group + choice + empty + data)" do
      before do
        stub_const("RngBookSpec", Module.new)
        described_class.to_models(
          schema,
          output_dir: dir,
          create_files: true,
          module_namespace: "RngBookSpec",
        )
        require File.join(dir, "rngbookspec_registry.rb")
        RngBookSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:schema) { File.read("spec/fixtures/xml/schema/rng/book.rng") }

      let(:hardcover_xml) do
        <<~XML
          <book isbn="978-0-13-110362-7">
            <title>The C Programming Language</title>
            <author>Brian Kernighan</author>
            <author>Dennis Ritchie</author>
            <publisher>Prentice Hall</publisher>
            <year>1988</year>
            <hardcover/>
          </book>
        XML
      end

      let(:paperback_xml) do
        <<~XML
          <book isbn="978-0-201-83595-3">
            <title>The Mythical Man-Month</title>
            <subtitle>Essays on Software Engineering</subtitle>
            <author>Frederick P. Brooks Jr.</author>
            <publisher>Addison-Wesley</publisher>
            <year>1995</year>
            <paperback/>
          </book>
        XML
      end

      it "compiles <attribute> as :attribute kind with map_attribute" do
        book = RngBookSpec::Book.from_xml(hardcover_xml)
        expect(book.isbn).to eq("978-0-13-110362-7")
      end

      it "handles <oneOrMore> as a collection attribute" do
        book = RngBookSpec::Book.from_xml(hardcover_xml)
        expect(book.author).to eq(["Brian Kernighan", "Dennis Ritchie"])
      end

      it "leaves <optional> elements absent when not in the XML" do
        book = RngBookSpec::Book.from_xml(hardcover_xml)
        expect(book.subtitle).to be_nil
      end

      it "reads <optional> elements when present" do
        book = RngBookSpec::Book.from_xml(paperback_xml)
        expect(book.subtitle).to eq("Essays on Software Engineering")
      end

      it "compiles <data type=\"integer\"/> as :integer (slice 3)" do
        book = RngBookSpec::Book.from_xml(hardcover_xml)
        expect(book.year).to eq(1988)
      end

      it "compiles <choice> alternatives, with empty-bodied elements as classes" do
        book = RngBookSpec::Book.from_xml(hardcover_xml)
        expect(book.hardcover).to be_a(RngBookSpec::Hardcover)
        expect(book.paperback).to be_nil
      end
    end

    context "with the person RNG schema (start ref + multi-define + cross-references)" do
      before do
        stub_const("RngPersonSpec", Module.new)
        described_class.to_models(
          schema,
          output_dir: dir,
          create_files: true,
          module_namespace: "RngPersonSpec",
        )
        require File.join(dir, "rngpersonspec_registry.rb")
        RngPersonSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:schema) { File.read("spec/fixtures/xml/schema/rng/person.rng") }

      let(:xml) do
        <<~XML
          <Person>
            <name>Alice</name>
            <age>30</age>
            <Address>
              <street>1 Main St</street>
              <city>Springfield</city>
            </Address>
          </Person>
        XML
      end

      it "generates one class per define" do
        expect(defined?(RngPersonSpec::Person)).to eq("constant")
        expect(defined?(RngPersonSpec::Address)).to eq("constant")
      end

      it "resolves <ref> as a typed attribute pointing to the referenced class" do
        person = RngPersonSpec::Person.from_xml(xml)
        expect(person.address).to be_a(RngPersonSpec::Address)
        expect(person.address.street).to eq("1 Main St")
        expect(person.address.city).to eq("Springfield")
      end

      it "round-trips XML through the cross-referenced classes" do
        person = RngPersonSpec::Person.from_xml(xml)
        expect(person.to_xml).to be_xml_equivalent_to(xml)
      end
    end

    context "with the integer_range RNG schema (restrictions + enumerations as SimpleType subclasses)" do
      before do
        stub_const("RngRestrictionSpec", Module.new)
        described_class.to_models(
          schema,
          output_dir: dir,
          create_files: true,
          module_namespace: "RngRestrictionSpec",
        )
        require File.join(dir, "rngrestrictionspec_registry.rb")
        RngRestrictionSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:schema) { File.read("spec/fixtures/xml/schema/rng/integer_range.rng") }

      it "generates a SimpleType subclass for <data> with restrictions" do
        src = File.read(File.join(dir, "rngrestrictionspec", "st_integer_range.rb"))
        expect(src).to include("class StIntegerRange < Lutaml::Model::Type::Integer")
        expect(src).to include("options[:min] = 1")
        expect(src).to include("options[:max] = 255")
      end

      it "generates a SimpleType subclass for <choice> of <value> enumerations" do
        src = File.read(File.join(dir, "rngrestrictionspec", "st_color.rb"))
        expect(src).to include("class StColor < Lutaml::Model::Type::String")
        expect(src).to include('options[:values] = [super("red"), super("green"), super("blue")]')
      end

      it "references SimpleTypes by registered symbol from the consuming class" do
        src = File.read(File.join(dir, "rngrestrictionspec", "thing.rb"))
        expect(src).to include("attribute :val, :st_integer_range")
        expect(src).to include("attribute :color, :st_color")
      end

      it "accepts XML that satisfies the restrictions" do
        thing = RngRestrictionSpec::Thing.from_xml(
          '<thing val="42"><color>red</color></thing>',
        )
        expect(thing.val).to eq(42)
        expect(thing.color).to eq("red")
      end

      it "raises MaxBoundError for out-of-range integers" do
        expect do
          RngRestrictionSpec::Thing.from_xml(
            '<thing val="500"><color>red</color></thing>',
          )
        end.to raise_error(Lutaml::Model::Type::MaxBoundError)
      end

      it "raises InvalidValueError for non-enum values" do
        expect do
          RngRestrictionSpec::Thing.from_xml(
            '<thing val="42"><color>purple</color></thing>',
          )
        end.to raise_error(Lutaml::Model::Type::InvalidValueError)
      end
    end

    context "with inline restrictions (anonymous SimpleType emission)" do
      let(:rng) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="game">
                <attribute name="age">
                  <data type="integer">
                    <param name="minInclusive">3</param>
                    <param name="maxInclusive">18</param>
                  </data>
                </attribute>
                <element name="rating">
                  <choice>
                    <value>E</value>
                    <value>T</value>
                    <value>M</value>
                  </choice>
                </element>
              </element>
            </start>
          </grammar>
        RNG
      end

      let(:sources) { described_class.to_models(rng) }

      it "generates anonymous SimpleTypes named after the host element/attribute" do
        expect(sources.keys).to contain_exactly("Game", "AgeType", "RatingType")
      end

      it "references inline restrictions by registered type symbol" do
        expect(sources["Game"]).to include("attribute :age, :age_type")
        expect(sources["Game"]).to include("attribute :rating, :rating_type")
      end

      it "emits the inline integer restriction as a Type::Integer subclass" do
        expect(sources["AgeType"]).to include("class AgeType < Lutaml::Model::Type::Integer")
        expect(sources["AgeType"]).to include("options[:min] = 3")
        expect(sources["AgeType"]).to include("options[:max] = 18")
      end

      it "emits the inline enumeration as a Type::String subclass with values" do
        expect(sources["RatingType"]).to include("class RatingType < Lutaml::Model::Type::String")
        expect(sources["RatingType"]).to include('options[:values] = [super("E"), super("T"), super("M")]')
      end
    end

    context "with the FullNameType regression fixture from issue #9" do
      let(:sources) do
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/full_name.rng"),
        )
      end

      it "preserves document order in the XML mappings" do
        expected_order = %w[
          abbrev prefix forename initials surname addition
          completeName biblionote variantname
        ]
        mapping_lines = sources["FullNameType"].lines.grep(/map_element "/)
        actual_order = mapping_lines.map { |l| l[/map_element "(\w+)"/, 1] }
        expect(actual_order).to eq(expected_order)
      end

      it "wraps grouped mappings in `sequence do ... end` inside the xml block" do
        # The <group> inside <choice> becomes a sequence wrapper in the XML
        # mapping section (matching XSD compiler's behavior).
        xml_block = sources["FullNameType"][/xml do.*?^  end/m]
        expect(xml_block).to include("sequence do")
        seq_block = xml_block[/sequence do.*?end/m]
        order = seq_block.scan(/map_element "(\w+)"/).flatten
        expect(order).to eq(%w[prefix forename initials surname addition])
      end

      it "emits choice alternatives in document order" do
        # The <choice> contains a <group>(prefix, forename, initials, surname,
        # addition) followed by completeName. After flattening (matching the
        # XSD compiler's behavior), all six appear in document order inside
        # the choice block.
        choice_block = sources["FullNameType"][/choice do.*?end/m]
        expect(choice_block).not_to be_nil
        attrs = choice_block.scan(/attribute :(\w+)/).flatten
        expect(attrs).to eq(
          %w[prefix forename formatted_initials surname addition complete_name],
        )
      end
    end

    context "with a namespaced grammar (slice 4i)" do
      let(:rng) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0" ns="http://example.com/books">
            <start>
              <element name="book">
                <element name="title"><text/></element>
              </element>
            </start>
          </grammar>
        RNG
      end

      let(:sources) { described_class.to_models(rng) }

      it "generates a XmlNamespace subclass for the grammar ns" do
        ns_name = sources.keys.find { |k| k.include?("Namespace") }
        expect(ns_name).not_to be_nil
        expect(sources[ns_name]).to include("< Lutaml::Xml::W3c::XmlNamespace")
        expect(sources[ns_name]).to include('uri "http://example.com/books"')
      end

      it "references the namespace class from each generated class" do
        expect(sources["Book"]).to match(/namespace \w+Namespace/)
      end

      it "adds a require_relative for the namespace class" do
        expect(sources["Book"]).to match(/require_relative ".*namespace"/)
      end
    end

    context "with documentation annotations (slice 4h)" do
      let(:rng) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0"
                   xmlns:a="http://relaxng.org/ns/compatibility/annotations/1.0">
            <start>
              <element name="book">
                <a:documentation>A book record with title and author.</a:documentation>
                <element name="title">
                  <a:documentation>The book title.</a:documentation>
                  <text/>
                </element>
                <element name="author">
                  <a:documentation>The book author.</a:documentation>
                  <text/>
                </element>
              </element>
            </start>
          </grammar>
        RNG
      end

      let(:sources) { described_class.to_models(rng) }

      it "emits class-level documentation as a Ruby comment above the class" do
        expect(sources["Book"]).to include("# A book record with title and author.\nclass Book")
      end

      it "emits attribute-level documentation as a Ruby comment above the attribute" do
        expect(sources["Book"]).to include("# The book title.\n  attribute :title")
        expect(sources["Book"]).to include("# The book author.\n  attribute :author")
      end
    end

    context "with the paragraph RNG schema (<mixed>)" do
      before do
        stub_const("RngParaSpec", Module.new)
        described_class.to_models(
          schema,
          output_dir: dir,
          create_files: true,
          module_namespace: "RngParaSpec",
        )
        require File.join(dir, "rngparaspec_registry.rb")
        RngParaSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:schema) { File.read("spec/fixtures/xml/schema/rng/paragraph.rng") }

      it "emits mixed_content for the <mixed> wrapper" do
        para_source = File.read(File.join(dir, "rngparaspec", "para.rb"))
        expect(para_source).to include("mixed_content")
      end
    end

    context "when classes are generated but files are not created" do
      let(:classes_hash) do
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/address_book.rng"),
        )
      end

      it "returns a Hash of class_name => Ruby source" do
        expect(classes_hash).to be_a(Hash)
        expect(classes_hash.keys).to contain_exactly(
          "AddressBook", "Card", "CardContent"
        )
        classes_hash.each_value { |src| expect(src).to start_with("# frozen_string_literal: true") }
      end
    end

    context "round-trip with Lutaml::Xml::Schema::RelaxngSchema.generate" do
      before do
        stub_const("RngRtAddress", Class.new(Lutaml::Model::Serializable) do
          attribute :street, :string
          attribute :city, :string

          xml do
            element "RngRtAddress"
            map_element "street", to: :street
            map_element "city", to: :city
          end
        end)

        stub_const("RngRtPerson", Class.new(Lutaml::Model::Serializable) do
          attribute :name, :string
          attribute :age, :integer
          attribute :address, RngRtAddress

          xml do
            element "RngRtPerson"
            map_element "name", to: :name
            map_element "age", to: :age
            map_element "RngRtAddress", to: :address
          end
        end)
      end

      it "round-trips primitive-typed attributes through generate + compile" do
        rng = Lutaml::Xml::Schema::RelaxngSchema.generate(RngRtPerson)
        sources = described_class.to_models(rng)

        expect(sources["RngRtPerson"]).to include("attribute :name, :string")
        expect(sources["RngRtPerson"]).to include("attribute :age, :integer")
      end

      it "round-trips typed reference attributes" do
        rng = Lutaml::Xml::Schema::RelaxngSchema.generate(RngRtPerson)
        sources = described_class.to_models(rng)

        expect(sources["RngRtPerson"]).to include(
          "attribute :rng_rt_address, RngRtAddress",
        )
      end
    end

    context "e2e: namespaced grammar loads + parses namespaced XML" do
      before do
        stub_const("RngNamespacedSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/namespaced.rng"),
          output_dir: dir,
          create_files: true,
          module_namespace: "RngNamespacedSpec",
        )
        require File.join(dir, "rngnamespacedspec_registry.rb")
        RngNamespacedSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:xml) do
        <<~XML
          <book xmlns="http://example.com/books" isbn="978-0-13-110362-7">
            <title>K&amp;R C</title>
          </book>
        XML
      end

      it "generates a namespace class and uses it in the generated model" do
        expect(defined?(RngNamespacedSpec::ComExampleBooksNamespace)).to eq("constant")
        expect(defined?(RngNamespacedSpec::Book)).to eq("constant")
      end

      it "parses namespaced XML through the generated classes" do
        book = RngNamespacedSpec::Book.from_xml(xml)
        expect(book.isbn).to eq("978-0-13-110362-7")
        expect(book.title).to eq("K&R C")
      end

      it "emits XML in the declared namespace on the root element" do
        book = RngNamespacedSpec::Book.from_xml(xml)
        expect(book.to_xml).to include('xmlns="http://example.com/books"')
      end
    end

    context "e2e: mixed content loads + parses mixed XML" do
      before do
        stub_const("RngMixedSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/paragraph.rng"),
          output_dir: dir,
          create_files: true,
          module_namespace: "RngMixedSpec",
        )
        require File.join(dir, "rngmixedspec_registry.rb")
        RngMixedSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }

      it "loads a Para class with mixed_content enabled" do
        expect(defined?(RngMixedSpec::Para)).to eq("constant")
        para = RngMixedSpec::Para.from_xml(
          "<para>Hello <emph>world</emph>!</para>",
        )
        expect(para).not_to be_nil
      end
    end

    context "e2e: inline restrictions enforce constraints at parse time" do
      before do
        stub_const("RngInlineSpec", Module.new)
        described_class.to_models(
          rng,
          output_dir: dir,
          create_files: true,
          module_namespace: "RngInlineSpec",
        )
        require File.join(dir, "rnginlinespec_registry.rb")
        RngInlineSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }
      let(:rng) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="game">
                <attribute name="age">
                  <data type="integer">
                    <param name="minInclusive">3</param>
                    <param name="maxInclusive">18</param>
                  </data>
                </attribute>
                <element name="rating">
                  <choice>
                    <value>E</value>
                    <value>T</value>
                    <value>M</value>
                  </choice>
                </element>
              </element>
            </start>
          </grammar>
        RNG
      end

      it "loads anonymous Type::Integer and Type::String subclasses" do
        expect(defined?(RngInlineSpec::AgeType)).to eq("constant")
        expect(defined?(RngInlineSpec::RatingType)).to eq("constant")
      end

      it "accepts XML satisfying the inline integer + enum restrictions" do
        game = RngInlineSpec::Game.from_xml(
          '<game age="12"><rating>T</rating></game>',
        )
        expect(game.age).to eq(12)
        expect(game.rating).to eq("T")
      end

      it "rejects XML violating the inline integer minInclusive" do
        expect do
          RngInlineSpec::Game.from_xml('<game age="1"><rating>T</rating></game>')
        end.to raise_error(Lutaml::Model::Type::MinBoundError)
      end

      it "rejects XML with a value outside the inline enumeration" do
        expect do
          RngInlineSpec::Game.from_xml(
            '<game age="12"><rating>X</rating></game>',
          )
        end.to raise_error(Lutaml::Model::Type::InvalidValueError)
      end
    end

    context "e2e: FullNameType (issue #9) loads + round-trips XML" do
      before do
        stub_const("RngFullNameSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/full_name.rng"),
          output_dir: dir,
          create_files: true,
          module_namespace: "RngFullNameSpec",
        )
        require File.join(dir, "rngfullnamespec_registry.rb")
        RngFullNameSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }

      it "loads the FullNameType class with all referenced defines" do
        %w[FullNameType NameAbbreviation Prefix Forename FormattedInitials
           Surname Addition CompleteName Biblionote Variantname].each do |c|
          expect(RngFullNameSpec.const_defined?(c)).to be(true), "missing #{c}"
        end
      end

      it "parses XML using the group/choice/zeroOrMore structure" do
        xml = <<~XML
          <fullname>
            <abbrev>Dr.</abbrev>
            <prefix>von</prefix>
            <forename>Alice</forename>
            <surname>Smith</surname>
            <biblionote>note 1</biblionote>
          </fullname>
        XML
        obj = RngFullNameSpec::FullNameType.from_xml(xml)
        expect(obj.name_abbreviation.content).to eq("Dr.")
        expect(obj.prefix.first.content).to eq("von")
        expect(obj.forename.first.content).to eq("Alice")
        expect(obj.surname.content).to eq("Smith")
        expect(obj.biblionote.first.content).to eq("note 1")
      end
    end

    context "e2e: union types load + cast across member types" do
      before do
        stub_const("RngUnionSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/union.rng"),
          output_dir: dir,
          create_files: true,
          module_namespace: "RngUnionSpec",
        )
        require File.join(dir, "rngunionspec_registry.rb")
        RngUnionSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }

      it "generates a Lutaml::Model::Type::Value subclass for the union define" do
        expect(defined?(RngUnionSpec::IntOrString)).to eq("constant")
        expect(RngUnionSpec::IntOrString.ancestors).to include(Lutaml::Model::Type::Value)
      end

      it "casts integer-shaped values to Integer" do
        thing = RngUnionSpec::Thing.from_xml("<thing><count>42</count></thing>")
        expect(thing.count).to eq(42)
      end

      it "casts non-integer values as String" do
        thing = RngUnionSpec::Thing.from_xml("<thing><count>hello</count></thing>")
        expect(thing.count).to eq("hello")
      end
    end

    context "e2e: fixed-value attribute uses default + round-trips" do
      before do
        stub_const("RngFixedSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/fixed_value.rng"),
          output_dir: dir,
          create_files: true,
          module_namespace: "RngFixedSpec",
        )
        require File.join(dir, "rngfixedspec_registry.rb")
        RngFixedSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }

      it "applies the default value when the attribute is omitted from XML" do
        thing = RngFixedSpec::Thing.from_xml("<thing><name>X</name></thing>")
        expect(thing.version).to eq("1.0")
      end

      it "preserves an explicit attribute value" do
        thing = RngFixedSpec::Thing.from_xml(
          '<thing version="1.0"><name>X</name></thing>',
        )
        expect(thing.version).to eq("1.0")
      end
    end

    context "e2e: load_classes: true (no files) loads classes into a tmp module" do
      let!(:result) do
        stub_const("RngLoadClassesSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rng/address_book.rng"),
          load_classes: true,
          module_namespace: "RngLoadClassesSpec",
        )
      end

      it "returns generated source per class" do
        expect(result).to be_a(Hash)
        expect(result.keys).to contain_exactly("AddressBook", "Card", "CardContent")
      end

      it "loads the namespaced module and registers classes" do
        expect(defined?(RngLoadClassesSpec::AddressBook)).to eq("constant")
        expect(defined?(RngLoadClassesSpec::Card)).to eq("constant")
      end

      it "the loaded classes can parse XML end-to-end" do
        book = RngLoadClassesSpec::AddressBook.from_xml(
          "<addressBook><card><name>X</name><email>x@y</email></card></addressBook>",
        )
        expect(book.card.first.name).to eq("X")
      end
    end

    context "e2e: list type compiles + tolerates whitespace-separated XML" do
      let(:dir) { Dir.mktmpdir }

      before do
        stub_const("RngListSpec", Module.new)
      end

      after do
        FileUtils.rm_rf(dir)
      end

      it "compiles a grammar with <list> without crashing" do
        expect do
          described_class.to_models(
            File.read("spec/fixtures/xml/schema/rng/list_type.rng"),
            output_dir: dir,
            create_files: true,
            module_namespace: "RngListSpec",
          )
          require File.join(dir, "rnglistspec_registry.rb")
          RngListSpec.register_all
        end.not_to raise_error
        expect(defined?(RngListSpec::Tags)).to eq("constant")
      end
    end

    context "via Schema.from_relaxng entry point" do
      it "delegates through the registered method" do
        result = Lutaml::Model::Schema.from_relaxng(
          File.read("spec/fixtures/xml/schema/rng/address_book.rng"),
        )
        expect(result).to be_a(Hash)
        expect(result.keys).to contain_exactly("AddressBook", "Card", "CardContent")
      end
    end
  end
end
