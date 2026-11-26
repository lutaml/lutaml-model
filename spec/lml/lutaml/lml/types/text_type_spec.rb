# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lutaml::Lml::Types::TextType do
  def cast(text)
    described_class.cast(text)
  end

  it 'unescapes \\\\{ and \\\\}' do
    expect(cast('a \\{foo\\} b')).to eq('a {foo} b')
  end

  it 'strips leading/trailing whitespace per line and rejoins' do
    expect(cast("one\n  two  \n\tthree")).to eq("one\ntwo\nthree")
  end

  it 'passes nil through' do
    expect(cast(nil)).to be_nil
  end

  it 'casts on model assignment' do
    attr = Lutaml::Lml::TopElementAttribute.new
    attr.definition = '  raw \\{ x \\}  '
    expect(attr.definition).to eq('raw { x }')
  end

  it 'casts on model construction' do
    attr = Lutaml::Lml::TopElementAttribute.new(definition: '\\{y\\}')
    expect(attr.definition).to eq('{y}')
  end

  it 'round-trips through yaml without mapping procs' do
    klass = Lutaml::Lml::UmlClass.new(name: 'P', definition: 'kept \\{ z \\}')
    restored = Lutaml::Lml::UmlClass.from_yaml(klass.to_yaml)
    expect(restored.definition).to eq('kept { z }')
  end

  it 'omits nil definitions from yaml' do
    yaml = Lutaml::Lml::UmlClass.new(name: 'P').to_yaml
    expect(yaml).not_to include('definition')
  end
end
