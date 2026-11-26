# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe 'RS 3010 serialization mappings' do
  def compile_lml(src)
    file = Tempfile.new(%w[s .lml])
    file.write(src)
    file.rewind
    compiler = Lutaml::Lml::ModelCompiler.new
    compiler.compile(file)
    compiler
  ensure
    file.close!
  end

  let(:compiler) do
    compile_lml(<<~LML)
      models Ceramics {
        namespace CeramicsNs {
          uri "http://example.com/ceramics"
          prefix "cer"
        }

        class Ceramic {
          attribute location, String
          attribute kiln, String
          attribute notes, String
        }
      }

      mapping xml Ceramic {
        element "ceramic"
        namespace CeramicsNs
        map_element "location" location
        map_attribute "kiln" kiln
        map_content notes
      }

      mapping key_value Ceramic {
        map "full-name" location
      }
    LML
  end

  it 'emits the mapped element name, wire names, attribute and content' do
    klass = compiler.compiled_classes['Ceramic']
    xml = klass.new(location: 'Paris', kiln: 'Electric', notes: 'fine').to_xml
    expect(xml).to include('<ceramic')
    expect(xml).to include('kiln="Electric"')
    expect(xml).to include('<location')
    expect(xml).to include('Paris')
    expect(xml).to include('fine</ceramic>')
  end

  it 'emits the key-value mapping wire names' do
    klass = compiler.compiled_classes['Ceramic']
    json = klass.new(location: 'Paris', kiln: 'E', notes: 'n').to_json
    expect(json).to include('"full-name"')
    expect(json).to include('Paris')
  end

  it 'links sibling mappings by target and namespaces by context reference' do
    mapping = compiler.instance_variable_get(:@serialization_mappings).first
    expect(mapping.format).to eq('xml')
    expect(mapping.target).to eq('Ceramic')
    expect(mapping.element_name).to eq('ceramic')
    expect(mapping.namespace_ref).to eq('CeramicsNs')
  end

  it 'accepts the in-class mapping shortcut targeting the enclosing class' do
    compiler = compile_lml(<<~LML)
      models M {
        class Tile {
          attribute code, String

          mapping xml {
            element "tile"
          }
        }
      }
    LML
    xml = compiler.compiled_classes['Tile'].new(code: 'C1').to_xml
    expect(xml).to include('<tile')
  end

  it 'raises on an ambiguous default namespace' do
    expect do
      compile_lml(<<~LML)
        models M {
          namespace A {
            uri "http://example.com/a"
            prefix "a"
          }
          namespace B {
            uri "http://example.com/b"
            prefix "b"
          }

          class Tile {
            attribute code, String
          }
        }

        mapping xml Tile {
          element "tile"
        }
      LML
    end.to raise_error(ArgumentError, /ambiguous default namespace/)
  end

  it 'keeps the legacy in-class map line syntax working' do
    compiler = compile_lml(<<~LML)
      models M {
        class Widget {
          attribute name { type String cardinality 1 }

          mapping yaml { map "full-name", to: "name" }
        }
      }
    LML
    klass = compiler.compiled_classes['Widget']
    yaml = klass.new(name: 'w').to_yaml
    expect(yaml).to include('full-name')
  end
end
