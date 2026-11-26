# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RS 3001 typed references (par. Value type)' do
  def parse(src)
    Lutaml::Lml.parse_document(StringIO.new(src))
  end

  let(:doc) do
    parse(<<~LML)
      instances {
        Product "a" {
          id = "A"
        }
        Product "b" {
          id = "B"
          same = ref:(a.id)
          full = reference:(a)
        }
        Item "listy" {
          refs = [reference:(a.id), ref:(b.id)]
        }
      }
    LML
  end

  it 'exposes a typed Reference per attribute' do
    b = doc.instances.instances.find { |i| i.name == 'b' }
    same = b.attributes.find { |a| a.name == 'same' }
    full = b.attributes.find { |a| a.name == 'full' }
    expect(same.reference).to be_a(Lutaml::Lml::Reference)
    expect(same.reference.path).to eq('a.id')
    expect(same.reference.segments).to eq(%w[a id])
    expect(full.reference.path).to eq('a')
  end

  it 'returns nil for non-reference values' do
    a = doc.instances.instances.find { |i| i.name == 'a' }
    id = a.attributes.find { |attr| attr.name == 'id' }
    expect(id.reference).to be_nil
  end

  it 'sees references inside list values' do
    item = doc.instances.instances.find { |i| i.name == 'listy' }
    refs = item.attributes.find { |attr| attr.name == 'refs' }
    expect(refs.reference.path).to eq('a.id')
  end

  it 'round trips references through LML emission' do
    emitted = Lutaml::Lml::Format::Adapter::StandardAdapter.new(
      {
        'same' => { reference: 'a.id' },
        'refs' => [{ reference: 'a.id' }, { reference: 'b.id' }]
      }
    )
    lml = emitted.to_lml
    expect(lml).to include('same = ref:(a.id)')
    expect(lml).to include('ref:(a.id)')
    expect(lml).to include('ref:(b.id)')
    reparsed = parse("instances {\n#{lml}\n}\n")
    expect(reparsed).to be_a(Lutaml::Lml::Document)
  end
end
