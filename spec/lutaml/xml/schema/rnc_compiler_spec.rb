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

    context "with an inline start containing a named reference" do
      let(:schema) do
        <<~RNC
          item = element item { text }
          start = element root { item* }
        RNC
      end

      it "generates the root model, not just the referenced child" do
        sources = described_class.to_models(schema)

        expect(sources.keys).to contain_exactly("Root", "Item")
        expect(sources["Root"]).to include("class Root")
        expect(sources["Root"]).to include('map_element "item", to: :item')
      end
    end

    context "with a ref-only inline start defined after its target" do
      let(:schema) do
        <<~RNC
          library = element library { text }
          start = library
        RNC
      end

      it "roots the referenced define without emitting a Start class" do
        sources = described_class.to_models(schema)

        expect(sources.keys).to include("Library")
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

      it "treats an attribute choice mixing text with a fixed value as a string" do
        expect(sources["Book"]).to include("attribute :indent, :string")
        expect(sources["Book"]).to include('map_attribute "indent", to: :indent')
        expect(sources.keys).not_to include("IndentType")
      end

      it "preserves xml-prefixed attributes in the XML mapping" do
        expect(sources["Book"]).to include("attribute :xml_lang")
        expect(sources["Book"]).to include('map_attribute "xml:lang", to: :xml_lang')
      end

      it "normalizes escaped identifiers into generated class names" do
        expect(sources.keys).to include("List")
        expect(sources["Book"]).to include("attribute :list, List")
      end

      it "reports the annotation compatibility warning" do
        warnings = []
        described_class.to_models(
          File.read("spec/fixtures/xml/schema/rnc/book_features.rnc"),
          warnings: warnings,
        )

        expect(warnings).to include(
          "RNC annotations are ignored by compatibility preprocessing.",
        )
        expect(warnings).not_to include(
          a_string_matching(%r{attribute text/value choices}),
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
        end.to raise_error(/Include file not found: .*missing\.rnc/)
      end

      it "raises a clear error for circular includes" do
        circular_path =
          "spec/fixtures/xml/schema/rnc/includes/circular_a.rnc"

        expect do
          described_class.to_models(File.read(circular_path), location: circular_path)
        end.to raise_error(/Circular include detected: .*circular_a\.rnc/)
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

    context "with an attribute in a foreign namespace" do
      let(:source) do
        %(namespace ex = "urn:test"\n) +
          %(start = element root { attribute ex:code { text } })
      end

      it "generates a namespaced value type for the attribute" do
        sources = described_class.to_models(source)

        code_type = sources.keys.find { |k| k.include?("Type") }
        expect(code_type).not_to be_nil
        expect(sources[code_type]).to match(/namespace \w+Namespace/)
        expect(sources[code_type]).to match(/require_relative ".*namespace"/)
        expect(sources["Root"]).to include('map_attribute "code", to: :code')
      end

      it "round-trips the foreign-namespace attribute (parse + fresh serialize)" do
        stub_const("RncForeignNs", Module.new)
        described_class.to_models(
          source, load_classes: true, module_namespace: "RncForeignNs"
        )

        parsed = RncForeignNs::Root.from_xml(%(<root xmlns:ex="urn:test" ex:code="q"/>))
        expect(parsed.code).to eq("q")

        # The attribute round-trips in its namespace; the emitted prefix is a
        # generated one (rng does not expose the source prefix), so match the
        # URI and a namespace-qualified `code` attribute rather than "ex".
        out = RncForeignNs::Root.new(code: "f").to_xml
        expect(out).to match(/xmlns:\w+="urn:test"/)
        expect(out).to match(/\w+:code="f"/)
      end

      it "does not namespace a type shared with an unqualified member" do
        sources = described_class.to_models(<<~RNC)
          namespace ex = "urn:test"
          codeType = xsd:string { maxLength = "5" }
          start = element root {
            attribute plain { codeType },
            attribute ex:tagged { codeType }
          }
        RNC

        # The shared codeType must NOT gain a namespace (plain uses it
        # unqualified); the foreign attribute gets its own namespaced type.
        expect(sources["CodeType"]).not_to match(/namespace \w+Namespace/)
        namespaced = sources.keys.find do |k|
          k != "DefaultNamespace" && sources[k].match?(/namespace \w+Namespace/)
        end
        expect(namespaced).not_to be_nil
      end

      it "namespaces a foreign-ns attribute with inline facets via a subclass" do
        sources = described_class.to_models(
          %(namespace ex = "urn:test"\n) +
          %(start = element root { attribute ex:code { xsd:string { maxLength = "5" } } }),
        )

        # The inline restricted type is subclassed (not mutated) so a fresh
        # namespaced type inherits its constraints and carries the namespace.
        expect(sources["CodeType"]).not_to match(/namespace \w+Namespace/)
        subclass = sources.keys.find { |k| sources[k].match?(/class \w+ < CodeType/) }
        expect(subclass).not_to be_nil
        expect(sources[subclass]).to match(/namespace \w+Namespace/)
      end
    end

    context "with namespaced root and child elements" do
      let(:source) do
        %(namespace ex = "urn:test"\n) +
          %(start = element ex:root { element ex:child { text } })
      end

      it "declares a class-level namespace with qualified element form" do
        sources = described_class.to_models(source)
        ns_key = sources.keys.find { |k| k.include?("Namespace") }

        expect(sources["Root"]).to match(/namespace \w+Namespace/)
        expect(sources[ns_key]).to include('uri "urn:test"')
        expect(sources[ns_key]).to include("element_form_default :qualified")
      end

      it "round-trips root and child in their namespace" do
        stub_const("RncNsElem", Module.new)
        described_class.to_models(
          source, load_classes: true, module_namespace: "RncNsElem"
        )

        xml = %(<ex:root xmlns:ex="urn:test"><ex:child>hi</ex:child></ex:root>)
        expect(RncNsElem::Root.from_xml(xml).child).to eq("hi")

        out = RncNsElem::Root.new(child: "x").to_xml
        expect(out).to match(/xmlns(:\w+)?="urn:test"/)
        expect(out).not_to include('xmlns=""')
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
