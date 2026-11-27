# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "tmpdir"
require "tempfile"
require "fileutils"

RSpec.describe "LML Grammar" do
  # Use the actual Parser class (Full grammar) for testing
  let(:parser) { Lutaml::Lml }

  describe "Core grammar (.lutaml syntax)" do
    it "parses a minimal diagram" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram MyView { class Foo {} }")
      file.rewind
      doc = parser.parse(file)
      expect(doc).to be_a(Lutaml::Lml::Document)
      expect(doc.classes.first.name).to eq("Foo")
      file.close!
    end

    it "parses view as alias for diagram" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("view MyView { class Foo {} }")
      file.rewind
      doc = parser.parse(file)
      expect(doc).to be_a(Lutaml::Lml::Document)
      expect(doc.name).to eq("MyView")
      expect(doc.classes.first.name).to eq("Foo")
      file.close!
    end

    it "parses class stereotype" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class NamespacedClass <<MyNamespace>> {} }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.classes.first.name).to eq("NamespacedClass")
      expect(doc.classes.first.stereotype).to eq(["MyNamespace"])
      file.close!
    end

    it "marks a quoted attribute type as a literal" do
      file = Tempfile.new(%w[test .lutaml])
      file.write('diagram Test { class Q { +type: "footnote" } }')
      file.rewind
      doc = parser.parse(file)
      attr = doc.classes.first.attributes.first
      expect(attr.name).to eq("type")
      expect(attr.type).to eq("footnote")
      expect(attr.literal).to be(true)
      file.close!
    end

    it "leaves an unquoted attribute type as a type reference" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class Q { +type: footnote } }")
      file.rewind
      doc = parser.parse(file)
      attr = doc.classes.first.attributes.first
      expect(attr.type).to eq("footnote")
      expect(attr.literal).to be(false)
      file.close!
    end

    it "parses abstract class" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { abstract class MyBase {} }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.classes.first.name).to eq("MyBase")
      file.close!
    end

    it "parses multiple classes" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class A {} class B {} class C {} }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.classes.length).to eq(3)
      file.close!
    end

    it "parses attributes with visibility modifiers" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test {\n  class MyClass {\n    +publicAttr: String\n    -privateAttr: Integer\n  }\n}")
      file.rewind
      doc = parser.parse(file)
      attrs = doc.classes.first.attributes
      expect(by_name(attrs, "publicAttr").visibility).to eq("public")
      expect(by_name(attrs, "privateAttr").visibility).to eq("private")
      file.close!
    end

    it "parses attributes with cardinality" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class MyClass { items: String [0..*] } }")
      file.rewind
      doc = parser.parse(file)
      attr = doc.classes.first.attributes.first
      expect(attr.name).to eq("items")
      expect(attr.cardinality.min).to eq("0")
      expect(attr.cardinality.max).to eq("*")
      file.close!
    end

    it "parses enum with values" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { enum Color { RED GREEN BLUE } }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.enums.first.name).to eq("Color")
      file.close!
    end

    it "parses data_type" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { data_type Amount { value: Decimal } }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.data_types.first.name).to eq("Amount")
      file.close!
    end

    it "parses primitive type" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { primitive Integer }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.primitives.first.name).to eq("Integer")
      file.close!
    end

    it "parses diagram metadata" do
      file = Tempfile.new(%w[test .lutaml])
      file.write('diagram MyView { title "my diagram" caption "my caption" fontname "Arial" class Foo {} }')
      file.rewind
      doc = parser.parse(file)
      expect(doc.title).to eq("my diagram")
      expect(doc.caption).to eq("my caption")
      expect(doc.fontname).to eq("Arial")
      file.close!
    end

    it "parses definition blocks" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class MyClass { definition { multi line def } } }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.classes.first.definition).to include("multi line def")
      file.close!
    end

    it "parses comments" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test {\n  ** My comment\n  class Foo {}\n}")
      file.rewind
      doc = parser.parse(file)
      expect(doc.comments).to include("My comment")
      file.close!
    end

    it "parses associations" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test {\n  class Foo {}\n  class Bar {}\n  association MyAssoc {\n    owner Foo\n    member Bar\n  }\n}")
      file.rewind
      doc = parser.parse(file)
      expect(doc.associations.length).to eq(1)
      file.close!
    end
  end

  describe "Full grammar (.lml syntax)" do
    it "parses models block with class definitions" do
      file = Tempfile.new(%w[test .lml])
      file.write <<~LML
        models TestModel {
          class ValidationCheck {
            attribute dev_id {
              type String
              cardinality 1
            }
          }
        }
      LML
      file.rewind
      doc = parser.parse(file)
      expect(doc.name).to eq("TestModel")
      klass = doc.classes.find { |c| c.name == "ValidationCheck" }
      expect(klass).not_to be_nil
      file.close!
    end

    it "parses instances with collection" do
      file = Tempfile.new(%w[test .lml])
      file.write <<~LML
        instances {
          collection "test_suite" {
            includes [ "a", "b" ]
          }
        }
      LML
      file.rewind
      doc = parser.parse(file)
      expect(doc.instances).to be_a(Lutaml::Lml::InstanceCollection)
      file.close!
    end

    it "parses require statements" do
      file = Tempfile.new(%w[test .lml])
      file.write <<~LML
        require "deps.lml"
        models Test { class Foo {} }
      LML
      file.rewind
      doc = parser.parse(file)
      expect(doc.requires).to include("deps.lml")
      file.close!
    end

    it "parses single-quoted require statements" do
      file = Tempfile.new(%w[test .lml])
      file.write <<~LML
        require 'deps.lml'
        models Test { class Foo {} }
      LML
      file.rewind
      doc = parser.parse(file)
      expect(doc.requires).to include("deps.lml")
      file.close!
    end
  end

  describe "Grammar composition" do
    it "Full grammar parses .lutaml files (Core is a subset)" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class Foo { name: String } }")
      file.rewind
      expect { parser.parse(file) }.not_to raise_error
      file.close!
    end

    it "Full grammar parses .lml files (Instances extension)" do
      file = Tempfile.new(%w[test .lml])
      file.write("models TestModel { class Foo {} }")
      file.rewind
      expect { parser.parse(file) }.not_to raise_error
      file.close!
    end
  end

  describe "Edge cases" do
    it "handles empty diagram" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Empty {}")
      file.rewind
      expect { parser.parse(file) }.not_to raise_error
      file.close!
    end

    it "handles class names with spaces" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class Banking Information {} }")
      file.rewind
      expect { parser.parse(file) }.not_to raise_error
      file.close!
    end

    it "handles nested class bodies" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test {\n  class Outer {\n    innerAttr: String\n    class Inner {\n      deepAttr: Integer\n    }\n  }\n}")
      file.rewind
      expect { parser.parse(file) }.not_to raise_error
      file.close!
    end

    it "raises on invalid syntax" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("this is not valid syntax !!!")
      file.rewind
      expect { parser.parse(file) }.to raise_error(Lutaml::Lml::ParsingError)
      file.close!
    end

    it "handles empty class body" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("diagram Test { class Empty {} }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.classes.first.name).to eq("Empty")
      file.close!
    end

    it "handles include directives via preprocessor" do
      dir = Dir.mktmpdir
      shared = File.join(dir, "shared.lutaml")
      File.write(shared, "class Shared {}")
      main_file = Tempfile.new(%w[test .lutaml])
      main_file.write("diagram Test {\n  include #{shared}\n}")
      main_file.rewind
      doc = parser.parse(main_file)
      expect(doc.classes.map(&:name)).to include("Shared")
      main_file.close!
      FileUtils.rm_rf(dir)
    end
  end

  describe "View grammar (import/show/hide)" do
    it "parses view with import directive" do
      dir = Dir.mktmpdir
      file = Tempfile.new(%w[test .lutaml], dir)
      File.write(File.join(dir, "foo.lutaml"), "class Foo {}")
      file.write('view MyView { import "foo.lutaml" }')
      file.rewind
      doc = parser.parse(file)
      expect(doc.name).to eq("MyView")
      expect(doc.view_imports.map(&:path)).to eq(["foo.lutaml"])
      file.close!
      FileUtils.rm_rf(dir)
    end

    it "parses view with single-quoted import directive" do
      dir = Dir.mktmpdir
      file = Tempfile.new(%w[test .lutaml], dir)
      FileUtils.mkdir_p(File.join(dir, "models"))
      File.write(File.join(dir, "models", "foo.lutaml"), "class Foo {}")
      file.write("view MyView { import 'models/foo.lutaml' }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.view_imports.map(&:path)).to eq(["models/foo.lutaml"])
      file.close!
      FileUtils.rm_rf(dir)
    end

    it "parses view with multiple imports" do
      dir = Dir.mktmpdir
      file = Tempfile.new(%w[test .lutaml], dir)
      File.write(File.join(dir, "a.lutaml"), "class A {}")
      File.write(File.join(dir, "b.lutaml"), "class B {}")
      file.write("view MyView {\n  import \"a.lutaml\"\n  import \"b.lutaml\"\n}")
      file.rewind
      doc = parser.parse(file)
      expect(doc.view_imports.map(&:path)).to eq(["a.lutaml", "b.lutaml"])
      file.close!
      FileUtils.rm_rf(dir)
    end

    it "parses view with show directive" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("view MyView { show Foo, Bar, Baz }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.show_filter.entity_names).to eq(%w[Foo Bar Baz])
      file.close!
    end

    it "parses view with hide directive" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("view MyView { hide Quux }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.hide_filter.entity_names).to eq(%w[Quux])
      file.close!
    end

    it "parses view with import, show, hide, and inline class" do
      dir = Dir.mktmpdir
      file = Tempfile.new(%w[test .lutaml], dir)
      File.write(File.join(dir, "a.lutaml"), "class Foo {}\nclass Bar {}")
      file.write("view MyView {\n  import \"*.lutaml\"\n  show Foo, Bar, Inline\n  hide Baz\n  class Inline {}\n}")
      file.rewind
      doc = parser.parse(file)
      expect(doc.view_imports.map(&:path)).to eq(["*.lutaml"])
      expect(doc.show_filter.entity_names).to eq(%w[Foo Bar Inline])
      expect(doc.hide_filter.entity_names).to eq(%w[Baz])
      expect(doc.classes.map(&:name)).to contain_exactly("Inline", "Foo", "Bar")
      file.close!
      FileUtils.rm_rf(dir)
    end

    it "separates show and hide directives on the same line" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("view MyView { show Foo, Bar hide Baz }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.show_filter.entity_names).to eq(%w[Foo Bar])
      expect(doc.hide_filter.entity_names).to eq(%w[Baz])
      file.close!
    end

    it "does not parse 'important' as an import directive" do
      file = Tempfile.new(%w[test .lutaml])
      file.write('view MyView { important "x" }')
      file.rewind
      expect { parser.parse(file) }.to raise_error(Lutaml::Lml::ParsingError)
      file.close!
    end

    it "accepts qualified entity names in show lists" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("view MyView { show Foo::Bar, a.b.C }")
      file.rewind
      doc = parser.parse(file)
      expect(doc.show_filter.entity_names).to eq(["Foo::Bar", "a.b.C"])
      file.close!
    end

    it "composes view metadata with filter directives" do
      dir = Dir.mktmpdir
      file = Tempfile.new(%w[test .lutaml], dir)
      File.write(File.join(dir, "m.lutaml"), "class Foo {}\nclass Bar {}")
      file.write('view V { title "t" caption "c" fontname "Arial" import "m.lutaml" hide Bar }')
      file.rewind
      doc = parser.parse(file)
      expect(doc.title).to eq("t")
      expect(doc.caption).to eq("c")
      expect(doc.fontname).to eq("Arial")
      expect(doc.classes.map(&:name)).to eq(["Foo"])
      file.close!
      FileUtils.rm_rf(dir)
    end
  end

  describe "Bare model files" do
    it "parses top-level definitions with no enclosing block" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("class Foo { name: String }\nenum Color { RED GREEN }\nprimitive Time")
      file.rewind
      doc = parser.parse(file)
      expect(doc).to be_a(Lutaml::Lml::Document)
      expect(doc.classes.first.name).to eq("Foo")
      expect(doc.enums.first.name).to eq("Color")
      expect(doc.primitives.first.name).to eq("Time")
      file.close!
    end

    it "parses a top-level association in a bare file" do
      file = Tempfile.new(%w[test .lutaml])
      file.write("class Foo {}\nclass Bar {}\nassociation FooBar {\n  owner Foo\n  member Bar\n}")
      file.rewind
      doc = parser.parse(file)
      expect(doc.associations.length).to eq(1)
      expect(doc.associations.first.owner_end).to eq("Foo")
      file.close!
    end
  end

  describe "shipped grammar artifact" do
    it "is committed and in sync with lml.parg" do
      expect(File).to exist(Lutaml::Lml::Grammar::ARTIFACT_PATH),
             "run `rake parg` to (re)generate the shipped artifact"

      envelope = JSON.parse(File.read(Lutaml::Lml::Grammar::ARTIFACT_PATH))
      expect(envelope["source"]).to eq(File.read(Lutaml::Lml::Grammar::GRAMMAR_PATH)),
             "grammar/lml.artifact.json is stale; run `rake parg`"
    end

    it "is the artifact the grammar actually loads" do
      expect(Lutaml::Lml::Grammar.artifact.path)
        .to eq(Lutaml::Lml::Grammar::ARTIFACT_PATH)
    end

    it "loads under a non-UTF-8 process locale" do
      original = Encoding.default_external
      Lutaml::Lml::Grammar.instance_variable_set(:@artifact, nil)
      Encoding.default_external = Encoding::US_ASCII
      begin
        artifact = Lutaml::Lml::Grammar.artifact
        expect(artifact.path).to eq(Lutaml::Lml::Grammar::ARTIFACT_PATH)
      ensure
        Encoding.default_external = original
        Lutaml::Lml::Grammar.instance_variable_set(:@artifact, nil)
      end
    end
  end

  describe "MECE keyword separation" do
    let(:parg_source) { File.read(Lutaml::Lml::Grammar::GRAMMAR_PATH) }

    # Live keyword sets of the PARG grammar, classified by layer. The
    # .parg source is the single source of truth; these lists pin the
    # expected classification so a keyword cannot silently migrate
    # between the model layer and the instance layer.
    let(:core_keywords) do
      %w[
        abstract attribute caption class data_type diagram enum fontname
        interface owner owner_type member member_type primitive title view
      ].freeze
    end

    let(:instance_keywords) do
      %w[
        collection condition export extends format import includes instance
        instances models require template validation
      ].freeze
    end

    it "grammar defines all core keywords" do
      core_keywords.each do |keyword|
        expect(parg_source).to include(%("#{keyword}")),
                               "missing core keyword #{keyword.inspect}"
      end
    end

    it "grammar defines all instance keywords" do
      instance_keywords.each do |keyword|
        expect(parg_source).to include(%("#{keyword}")),
                               "missing instance keyword #{keyword.inspect}"
      end
    end

    it "keyword lists do not overlap (MECE)" do
      overlap = core_keywords & instance_keywords
      expect(overlap).to be_empty, "Expected no overlap but found: #{overlap.inspect}"
    end

    it "combined keywords cover all expected keywords" do
      all = core_keywords + instance_keywords
      expect(all.uniq.length).to eq(all.length), "Duplicate keywords found"
    end
  end

  describe "title and definition charset" do
    def parse_lml(src)
      file = Tempfile.new(%w[test .lml])
      file.write(src)
      file.rewind
      doc = Lutaml::Lml.parse(file)
      file.close!
      doc
    end

    it "parses a double-quoted title containing parentheses and commas" do
      doc = parse_lml(%(diagram T { title "MPFA Bibliographic Item (Offering Document)" class Foo {} }))
      expect(doc.title).to eq("MPFA Bibliographic Item (Offering Document)")
    end

    it "parses a single-quoted title containing parentheses" do
      doc = parse_lml(%(diagram T { title 'MPFA Bibliographic Item (Offering Document)' class Foo {} }))
      expect(doc.title).to eq("MPFA Bibliographic Item (Offering Document)")
    end

    it "parses a double-quoted title containing Unicode" do
      doc = parse_lml(%(diagram T { title "国家标准类别" class Foo {} }))
      expect(doc.title).to eq("国家标准类别")
    end

    it "parses definition text containing nested braces" do
      doc = parse_lml(<<~LML)
        diagram T {
          class Foo {
            definition {
              Format: "ZB{code}", where {code} is the profession code.
            }
          }
        }
      LML
      expect(doc.classes.first.definition).to include("ZB{code}")
    end

    it "parses definition text containing Unicode" do
      doc = parse_lml(<<~LML)
        diagram T {
          enum Scope {
            definition {
              Chinese national standard. 国家标准.
            }
            guojia {
              definition {
                国家标准
              }
            }
          }
        }
      LML
      expect(doc.enums.first.definition).to include("国家标准")
    end
  end
end
