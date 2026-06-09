require "rng"
require "spec_helper"
require "lutaml/model/schema"
require "tmpdir"

RSpec.describe Lutaml::Model::Schema::RncCompiler do
  before do
    default_ctx = Lutaml::Model::GlobalContext.context(:default)
    if default_ctx
      default_ctx.registry.clear
      Lutaml::Model::Type.register_builtin_types_in(default_ctx.registry)
    end
  end

  describe ".to_models" do
    context "with an RNC schema using named patterns and start |=" do
      let(:schema) { File.read("spec/fixtures/xml/schema/rnc/address_book.rnc") }
      let(:sources) { described_class.to_models(schema) }

      it "compiles RNC through the RNG compiler" do
        expect(sources.keys).to contain_exactly(
          "AddressBook", "Card", "Name", "Email"
        )
        expect(sources["AddressBook"]).to include("class AddressBook")
        expect(sources["AddressBook"]).to include('map_element "card", to: :card')
      end

      it "does not emit a synthetic Start class for the RNC start pattern" do
        expect(sources).not_to have_key("Start")
      end
    end

    context "with create_files output" do
      let(:dir) { Dir.mktmpdir }
      let(:schema) { File.read("spec/fixtures/xml/schema/rnc/address_book.rnc") }

      before do
        stub_const("RncAddressBookSpec", Module.new)
        described_class.to_models(
          schema,
          output_dir: dir,
          create_files: true,
          module_namespace: "RncAddressBookSpec",
        )
        require File.join(dir, "rncaddressbookspec_registry.rb")
        RncAddressBookSpec.register_all
      end

      after do
        FileUtils.rm_rf(dir)
      end

      it "writes namespaced files and registry output" do
        module_dir = File.join(dir, "rncaddressbookspec")
        expect(File).to exist(File.join(dir, "rncaddressbookspec_registry.rb"))
        expect(File).to exist(File.join(module_dir, "address_book.rb"))
        expect(File).to exist(File.join(module_dir, "card.rb"))
      end

      it "loads generated classes that can parse XML" do
        xml = <<~XML
          <addressBook>
            <card>
              <name>Alice</name>
              <email>alice@example.com</email>
            </card>
          </addressBook>
        XML

        book = RncAddressBookSpec::AddressBook.from_xml(xml)
        expect(book.card.first.name.content).to eq("Alice")
        expect(book.card.first.email.content).to eq("alice@example.com")
      end
    end

    context "with RNC-specific syntax used by RFC XML schemas" do
      let(:sources) do
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rnc/book_features.rnc"),
        )
      end

      it "accepts compatibility annotations before attributes" do
        expect(sources["Book"]).to include("class Book")
        expect(sources["Book"]).to include('map_attribute "format", to: :format')
      end

      it "normalizes attribute choices that mix text with fixed values" do
        expect(sources["Book"]).to include("attribute :indent, :string")
        expect(sources["Book"]).to include('map_attribute "indent", to: :indent')
      end

      it "preserves xml-prefixed attributes in the XML mapping" do
        expect(sources["Book"]).to include("attribute :xml_lang")
        expect(sources["Book"]).to include('map_attribute "xml:lang", to: :xml_lang')
      end

      it "normalizes escaped identifiers into generated class names" do
        expect(sources.keys).to include("List")
        expect(sources["Book"]).to include("attribute :list, List")
      end

      it "reports compatibility warnings for lossy RNC preprocessing" do
        warnings = []
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rnc/book_features.rnc"),
          warnings: warnings,
        )

        expect(warnings).to include(
          "RNC annotations are ignored by compatibility preprocessing.",
          "RNC attribute text/value choices are normalized to text; " \
          "literal alternatives are not enforced.",
        )
      end

      it "loads generated classes that parse normalized RNC mappings" do
        stub_const("RncFeatureSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rnc/book_features.rnc"),
          load_classes: true,
          module_namespace: "RncFeatureSpec",
        )

        xml = <<~XML
          <book xml:lang="en" indent="adaptive">
            <title>Example</title>
            <list>
              <item>First</item>
              <item>Second</item>
            </list>
          </book>
        XML

        book = RncFeatureSpec::Book.from_xml(xml)
        expect(book.xml_lang).to eq("en")
        expect(book.indent).to eq("adaptive")
        expect(book.title.content).to eq("Example")
        expect(book.list.item.map(&:content)).to eq(%w[First Second])
      end

      it "does not rewrite attributes with nested datatype parameter braces" do
        source = <<~RNC
          root =
            element root {
              attribute code { xsd:string { pattern = "[A-Z]+" } }
            }

          start |= root
        RNC

        sources = described_class.to_models(source)

        expect(sources.keys).to include("Root", "CodeType")
        expect(sources["Root"]).to include("attribute :code, :code_type")
      end
    end

    context "with include resolution through the location option" do
      let(:path) do
        "spec/fixtures/xml/schema/rnc/includes/library.rnc"
      end

      it "loads included RNC definitions before delegating to RngCompiler" do
        sources = described_class.to_models(File.read(path), location: path)

        expect(sources.keys).to include("Library", "Book", "Title")
        expect(sources["Library"]).to include("attribute :book, Book")
      end

      it "raises a clear error for missing include files" do
        expect do
          described_class.to_models(
            'include "missing.rnc"',
            location: "spec/fixtures/xml/schema/rnc/includes",
          )
        end.to raise_error(/RNC include file not found: .*missing\.rnc/)
      end

      it "raises a clear error for circular includes" do
        circular_path =
          "spec/fixtures/xml/schema/rnc/includes/circular_a.rnc"

        expect do
          described_class.to_models(File.read(circular_path), location: circular_path)
        end.to raise_error(/Circular RNC include detected: .*circular_a\.rnc/)
      end

      it "fails explicitly for unsupported include override blocks" do
        expect do
          described_class.to_models(
            'include "book.rnc" { start = book }',
            location: "spec/fixtures/xml/schema/rnc/includes",
          )
        end.to raise_error(/RNC include override blocks are not supported: book\.rnc/)
      end
    end

    context "with load_classes mode" do
      let!(:sources) do
        stub_const("RncLoadClassesSpec", Module.new)
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rnc/address_book.rnc"),
          load_classes: true,
          module_namespace: "RncLoadClassesSpec",
        )
      end

      it "returns generated source and loads constants" do
        expect(sources.keys).to contain_exactly(
          "AddressBook", "Card", "Name", "Email"
        )
        expect(defined?(RncLoadClassesSpec::AddressBook)).to eq("constant")
      end
    end

    context "with QName references and occurrence markers" do
      let(:preprocessor) { Lutaml::Model::Schema::RncCompiler::Preprocessor.new }

      it "wraps a valid prefixed reference around its occurrence marker" do
        result = preprocessor.call("element foo { xsd:string* }")

        expect(result.source).to include("(xsd:string)*")
      end

      it "does not wrap malformed multi-colon tokens as a single ref" do
        result = preprocessor.call("element foo { bad:thing:taco* }")

        expect(result.source).not_to include("(bad:thing:taco)*")
      end
    end

    context "with attribute-like syntax inside an RNC comment" do
      # Regression for the gsub-vs-scan bug: normalize_attribute_text_choices
      # used to walk the whole source unconditionally, so a commented example
      # was rewritten AND emitted a misleading TEXT_CHOICE_WARNING.
      it "does not rewrite or warn on attribute syntax inside a # comment" do
        source = <<~RNC
          # Old code: attribute foo { text | "literal" }
          start = element bar { text }
        RNC

        result = Lutaml::Model::Schema::RncCompiler::Preprocessor.new.call(source)

        expect(result.source).to include('attribute foo { text | "literal" }')
        expect(result.warnings).not_to include(
          "RNC attribute text/value choices are normalized to text; " \
          "literal alternatives are not enforced.",
        )
      end
    end

    context "with input text and a file location" do
      # Regression for the SourceResolver override bug: when caller passed
      # both `input` and `location:` pointing at a file, the resolver
      # silently read the file from disk and discarded the input.
      it "uses the caller-provided text, not the file contents" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "real_file.rnc")
          File.write(path, "start = element from_disk { text }")
          inline = "start = element from_inline { text }"

          sources = described_class.to_models(inline, location: path)

          expect(sources.keys).to include("FromInline")
          expect(sources.keys).not_to include("FromDisk")
        end
      end
    end

    context "with an invalid attribute QName" do
      # Direct-preprocessor test: integration would couple to the downstream
      # rng parser's error message for the malformed identifier.
      it "leaves malformed identifiers untouched in preprocessing" do
        source = 'attribute foo:bar:baz { text | "literal" }'
        result = Lutaml::Model::Schema::RncCompiler::Preprocessor.new.call(source)

        expect(result.source).to eq(source)
        expect(result.warnings).not_to include(
          "RNC attribute text/value choices are normalized to text; " \
          "literal alternatives are not enforced.",
        )
      end
    end

    context "via Schema.from_rnc entry point" do
      it "delegates through the registered XML schema method" do
        result = Lutaml::Model::Schema.from_rnc(
          File.read("spec/fixtures/xml/schema/rnc/address_book.rnc"),
        )

        expect(result.keys).to contain_exactly(
          "AddressBook", "Card", "Name", "Email"
        )
      end
    end
  end
end
