# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

LAYOUT_LML = <<~LML
  models M {
    class Outer {
      attribute inner, Inner { cardinality 1 }
      attribute inners, Inner { cardinality 0..n }
    }
    class Inner {
      attribute x, String
    }
  }
  instance Outer {
    inner = instance Inner { x = "one" }
    inners = [instance Inner { x = "a" }]
  }
LML

def compile_and_hydrate(lml)
  source = StringIO.new(lml)
  compiler = Lutaml::Lml::ModelCompiler.new
  compiler.compile(source)
  source.rewind
  compiler.hydrate(source)
end

# RS 3001 §String values / §Instance: an explicit null assignment
# denotes the null value; an unassigned optional attribute is absent;
# both hydrate to nil, and a present empty string stays empty.
RSpec.describe "null and absence semantics" do
  it "hydrates explicit null, absent, and present-empty distinctly" do
    require "lutaml/lml/format"
    compiled = Lutaml::Lml.compile(StringIO.new(<<~LML))
      models NullSemantics {
        class Fields {
          attribute null_note { type String cardinality 0..1 }
          attribute empty_note { type String cardinality 0..1 }
          attribute absent_note { type String cardinality 0..1 }
        }
      }
    LML
    klass = compiled["Fields"]
    inst = klass.from_lml(<<~LML)
      instance Data {
        null_note = null
        empty_note = ""
      }
    LML
    expect(inst.null_note).to be_nil
    expect(inst.empty_note).to eq("")
    expect(inst.absent_note).to be_nil
  end
end

RSpec.describe 'instance hydration semantics (issue #17)' do
  it 'hydrates nested instances under collection attributes as arrays' do
    hydrated = compile_and_hydrate(LAYOUT_LML)
    expect(hydrated.inners).to be_an(Array)
    expect(hydrated.inners.first.x).to eq('a')
  end

  it 'hydrates a scalar attribute with one nested instance as the object' do
    hydrated = compile_and_hydrate(LAYOUT_LML)
    expect(hydrated.inner.x).to eq('one')
    expect(hydrated.inner).not_to be_an(Array)
    expect(hydrated.inners).to be_an(Array)
  end

  it 'materializes inline maps as a Hash at the parse level (not corrupt text)' do
    doc = Lutaml::Lml.parse_document(StringIO.new(<<~LML))
      instance Cfg {
        settings = { a = "1"; b = "2" }
      }
    LML
    attr = doc.instance.attributes.first
    cargo = attr.value.respond_to?(:value) ? attr.value.value : attr.value
    expect(cargo).to eq(a: '1', b: '2')
  end

  it 'accumulates repeated instances blocks' do
    doc = Lutaml::Lml.parse_document(StringIO.new(<<~LML))
      instances {
        collection "A" {
          validation { condition "count >= 0" }
        }
      }
      instances {
        collection "B" {
          validation { condition "count >= 0" }
        }
      }
    LML
    expect(doc.instances.collections.map(&:name)).to eq(%w[A B])
  end

  it 'errors on duplicate collection names across instances blocks' do
    duplicate = "instances { collection \"A\" { } }\ninstances { collection \"A\" { } }\n"
    expect { Lutaml::Lml.parse_document(StringIO.new(duplicate)) }
      .to raise_error(Lutaml::Lml::Error, /duplicate collection name 'A'/)
  end

  # An untyped nested instance takes the enclosing attribute's type;
  # the raw-hash path would leave a `_name` key on the value and defeat
  # union member key-coverage.
  it 'hydrates an untyped nested instance under a typed attribute as the attribute class' do
    hydrated = compile_and_hydrate(<<~LML)
      models M {
        class Outer {
          attribute inner, Inner { cardinality 1 }
          attribute inners, Inner { cardinality 0..n }
        }
        class Inner {
          attribute x, String
        }
      }
      instance Outer {
        inner = instance { x = "one" }
        inners = [instance { x = "a" }, instance { x = "b" }]
      }
    LML
    expect(hydrated.inner).not_to be_a(Hash)
    expect(hydrated.inner.x).to eq('one')
    expect(hydrated.inners).to be_an(Array)
    expect(hydrated.inners.map(&:x)).to eq(%w[a b])
  end

  it 'hydrates an untyped nested instance under a union attribute via member key coverage' do
    compiler = Lutaml::Lml::ModelCompiler.new
    compiler.compile(StringIO.new(<<~LML))
      models M {
        class Holder {
          attribute placeholder, String
        }
        class Inner {
          attribute x, String
        }
      }
    LML
    holder = compiler.compiled_classes.fetch('Holder')
    inner = compiler.compiled_classes.fetch('Inner')
    holder.attribute :mixed, Lutaml::Model::Type::Union,
                     union_member_types: [inner, :string]

    typed = compiler.hydrate(StringIO.new(<<~LML))
      instance Holder {
        mixed = instance { x = "deep" }
      }
    LML
    expect(typed.mixed).to be_an_instance_of(inner)
    expect(typed.mixed.x).to eq('deep')

    scalar = compiler.hydrate(StringIO.new("instance Holder {\n  mixed = shallow\n}\n"))
    expect(scalar.mixed).to eq('shallow')
  end

  # Quoted attribute keys arrive from the grammar as {string: ...} capture
  # nodes (issue #78); they must be unwrapped, not stringified.
  it 'preserves quoted attribute keys verbatim, padding and emptiness included' do
    doc = Lutaml::Lml.parse_document(StringIO.new(<<~LML))
      instance R {
        data = instance {
          "  company name/address" = "Germany / DEU"
          "" = "Mr Stephan"
        }
      }
    LML
    data = doc.instance.each_attribute.find { |n, _| n == 'data' }
    entry = data[2].first
    names = []
    entry.each_attribute { |name, _| names << name }
    expect(names).to eq(['  company name/address', ''])
  end
end
