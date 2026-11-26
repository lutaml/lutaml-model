# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'parsanol'

RSpec.describe 'LML declarations (isa, defaults, derive, payloads, string_format)' do
  def compile_lml(source)
    file = Tempfile.new(%w[test .lml])
    file.write(source)
    file.rewind
    Lutaml::Lml::ModelCompiler.new.tap { |c| c.compile(file) }
  ensure
    file.close!
  end

  def write_grammar_artifact
    source = <<~PARG
      grammar CodeFmt version "1" {
        code = ( 1*%x30-39 ) as code
        entry code: code
        bindings code {
          code -> code (string)
        }
        test { accept "42" }
      }
    PARG
    document = Parsanol::PARG::Parser.new(source).parse
    envelope = Parsanol::PARG::Compiler.compile(document).envelope
    # A Tempfile is GC-unlinked when the object goes out of scope, so
    # the path must outlive the helper: a real directory file keeps the
    # artifact alive for the suite's duration.
    dir = Dir.mktmpdir('code-artifact')
    path = File.join(dir, 'code.artifact.json')
    File.write(path, JSON.generate(envelope.respond_to?(:to_h) ? envelope.to_h : envelope))
    path
  end

  describe 'isa instance-type override (L6)' do
    it 'routes hydration through isa and keeps type as data' do
      compiler = compile_lml(<<~LML)
        models M {
          class Item {
            attribute type { type String cardinality 0..1 }
            attribute size { type String cardinality 1 }
          }
        }
      LML
      data = Tempfile.new(%w[d .lml])
      data.write("instance Item {\n  isa Item\n  type = \"standard\"\n  size = \"L\"\n}\n")
      data.rewind
      item = compiler.hydrate(data)
      expect(item).to be_a(compiler.compiled_classes['Item'])
      expect(item.type).to eq('standard')
      expect(item.size).to eq('L')
    ensure
      data.close!
    end
  end

  describe 'attribute defaults and render_nil (L7b)' do
    it 'compiles declared default literals and render_nil' do
      compiler = compile_lml(<<~LML)
        models M {
          class C {
            attribute originator { type String cardinality 0..1 default "iso" }
            attribute remark { type String cardinality 0..1 render_nil true }
          }
        }
      LML
      options = compiler.compiled_classes['C'].attributes[:originator].options
      expect(options[:default]).to eq('iso')
      remark_rule = compiler.compiled_classes['C'].mappings_for(:yaml)
                            .mappings.find { |rule| rule.name == 'remark' }
      expect(remark_rule.render_nil).to be(true)
    end
  end

  describe 'derive declarations (L7b)' do
    it 'declares the attribute and records the derivation' do
      compiler = compile_lml(<<~LML)
        models M {
          class Doc {
            attribute urn { type String cardinality 0..1 }
            derive tiny: String
          }
        }
      LML
      klass = compiler.compiled_classes['Doc']
      expect(klass.attributes).to have_key(:tiny)
      expect(klass.derived_fields).to eq([:tiny])
    end
  end

  describe 'enum member payloads (L7a)' do
    it 'carries typed payloads on members' do
      compiler = compile_lml(<<~LML)
        models M {
          enum Stage {
            member_fields { abbreviation String  urn_segment String }
            draft10 { abbreviation = "WD"  urn_segment = "wd" }
            published { abbreviation = "IS"  urn_segment = "published" }
          }
        }
      LML
      stage = compiler.compiled_classes['Stage']
      expect(stage.draft10.abbreviation).to eq('WD')
      expect(stage.published.urn_segment).to eq('published')
    end

    it 'rejects undeclared payload fields' do
      expect do
        compile_lml(<<~LML)
          models M {
            enum Stage {
              member_fields { abbreviation String }
              draft10 { abbreviation = "WD"  oops = "x" }
            }
          }
        LML
      end.to raise_error(ArgumentError, /undeclared payload fields/)
    end
  end

  describe 'string_format declarations (L5)' do
    let(:artifact_path) { write_grammar_artifact }

    it 'registers a grammar-backed format on the class' do
      compiler = Lutaml::Lml::ModelCompiler.new(
        artifact_paths: { 'code_fmt' => artifact_path }
      )
      source = Tempfile.new(%w[test .lml])
      source.write(<<~LML)
        models M {
          class Widget {
            attribute code { type String cardinality 1 }
            string_format code_id {
              artifact "code_fmt"
              root "code"
            }
          }
        }
      LML
      source.rewind
      compiler.compile(source)
      widget = compiler.compiled_classes['Widget']
      expect(widget).to respond_to(:from_code_id)
      expect(widget.from_code_id('42').code).to eq('42')
    ensure
      source.close!
    end
  end

  describe 'RS 3001 canonical value construct' do
    it 'compiles value members with descriptions and payloads' do
      compiler = compile_lml(<<~LML)
        models M {
          enum Finish {
            member_fields { label String }
            value "Celadon" {
              definition "Pale green glaze"
              label = "cel"
            }
            value matte { definition "Non-reflective" }
            gloss
          }
        }
      LML
      finish = compiler.compiled_classes['Finish']
      expect(finish.values.map(&:name)).to eq(['Celadon', 'matte', 'gloss'])
      expect(finish.values.first.description).to eq('Pale green glaze')
      expect(finish.values.first.payload).to eq('label' => 'cel')
      expect(finish.matte.value).to eq('matte')
      expect(finish.gloss.value).to eq('gloss')
    end

    it 'treats quoted member names as canonical values with safe accessors' do
      compiler = compile_lml(<<~LML)
        models M {
          enum Glaze {
            value "Raku Glaze" { }
            plain
          }
        }
      LML
      glaze = compiler.compiled_classes['Glaze']
      expect(glaze.values.map(&:name)).to eq(['Raku Glaze', 'plain'])
      expect(glaze.Raku_Glaze.value).to eq('Raku Glaze')
    end
  end

  describe 'RS 3001 comma attribute form' do
    it 'compiles `attribute name, Type { ... }` like the keyword form' do
      compiler = compile_lml(<<~LML)
        models M {
          class Ceramic {
            attribute location, String { cardinality 0..n }
            attribute firing, String
          }
        }
      LML
      klass = compiler.compiled_classes['Ceramic']
      expect(klass.attributes.keys).to include(:location, :firing)
      inst = klass.new(location: 'kiln', firing: 'low')
      expect(inst.location).to eq(['kiln'])
      expect(inst.firing).to eq('low')
    end
  end

  describe 'RS 3001 attribute values argument' do
    it 'expands an inline value set into an anonymous enum' do
      compiler = compile_lml(<<~LML)
        models M {
          class Tile {
            attribute status, String { values { draft, published } }
          }
        }
      LML
      status_type = compiler.compiled_classes['Tile'].attributes[:status].type
      expect(status_type).to be_a(Class)
      expect(status_type.values.map(&:name)).to eq(%w[draft published])
    end

    it 'types the attribute with a referenced enum' do
      compiler = compile_lml(<<~LML)
        models M {
          enum Finish { celadon matte }
          class Tile {
            attribute finish, String { values Finish }
          }
        }
      LML
      finish_type = compiler.compiled_classes['Tile'].attributes[:finish].type
      expect(finish_type).to be(compiler.compiled_classes['Finish'])
    end
  end

  describe 'RS 3001 single-line definition' do
    it 'sets the entity definition from the quoted form' do
      doc = Lutaml::Lml.parse_document(<<~LML)
        models M {
          enum Stage {
            definition "Stage codes"
            draft
          }
        }
      LML
      expect(doc.enums.first.definition).to eq('Stage codes')
    end
  end

  describe 'RS 3001 ref: reference spelling' do
    it 'parses ref:(...) identically to reference:(...)' do
      src = lambda do |keyword|
        "instances {\n  Product \"p\" {\n    r = #{keyword}:(Product.id)\n  }\n}\n"
      end
      from_ref = Lutaml::Lml.parse_document(src.call('ref'))
      from_full = Lutaml::Lml.parse_document(src.call('reference'))
      ref_attr = from_ref.instances.instances.first.attributes.find { |a| a.name == 'r' }
      full_attr = from_full.instances.instances.first.attributes.find { |a| a.name == 'r' }
      expect(ref_attr.value.value).to eq(full_attr.value.value)
      expect(ref_attr.reference).to be_a(Lutaml::Lml::Reference)
      expect(ref_attr.reference.path).to eq('Product.id')
    end
  end

  describe 'enum from_table (L7a, artifact-table reference)' do
    it 'bakes artifact table rows as members at compile time' do
      artifact_path = write_grammar_artifact
      envelope = JSON.parse(File.read(artifact_path))
      envelope['tables'] = {
        'stages' => {
          'file' => 'stages.yaml',
          'rows' => [
            { 'name' => 'draft10', 'abbreviation' => 'WD', 'urn_segment' => 'wd' },
            { 'name' => 'published', 'abbreviation' => 'IS', 'urn_segment' => 'published' },
            { 'name' => 'withdrawn', 'abbreviation' => nil }
          ]
        }
      }
      File.write(artifact_path, JSON.generate(envelope))

      compiler = Lutaml::Lml::ModelCompiler.new(
        artifact_paths: { 'code_fmt' => artifact_path }
      )
      source = Tempfile.new(%w[test .lml])
      source.write(<<~LML)
        models M {
          enum Stage {
            member_fields { abbreviation String  urn_segment String }
            from_table "stages" {
              artifact "code_fmt"
            }
          }
        }
      LML
      source.rewind
      compiler.compile(source)

      stage = compiler.compiled_classes['Stage']
      expect(stage.draft10.abbreviation).to eq('WD')
      expect(stage.published.urn_segment).to eq('published')
      expect(stage.withdrawn.abbreviation).to be_nil
      expect(stage.values.map(&:name)).to eq(%w[draft10 published withdrawn])
    ensure
      source.close!
    end

    it 'rejects unknown table fields' do
      artifact_path = write_grammar_artifact
      envelope = JSON.parse(File.read(artifact_path))
      envelope['tables'] = {
        'stages' => { 'file' => 'stages.yaml', 'rows' => [{ 'name' => 'draft10', 'oops' => 'x' }] }
      }
      File.write(artifact_path, JSON.generate(envelope))

      compiler = Lutaml::Lml::ModelCompiler.new(
        artifact_paths: { 'code_fmt' => artifact_path }
      )
      source = Tempfile.new(%w[test .lml])
      source.write(<<~LML)
        models M {
          enum Stage {
            member_fields { abbreviation String }
            from_table "stages" {
              artifact "code_fmt"
            }
          }
        }
      LML
      source.rewind
      expect { compiler.compile(source) }.to raise_error(ArgumentError, /undeclared fields/)
    ensure
      source.close!
    end
  end
end
