# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Lutaml::Lml::EntityTypes do
  it 'registers all four entity models' do
    expect(described_class.all).to eq(
      [
        Lutaml::Lml::UmlClass,
        Lutaml::Lml::Enum,
        Lutaml::Lml::DataType,
        Lutaml::Lml::PrimitiveType,
      ],
    )
  end

  it 'indexes models by their declared entity_type symbol' do
    expect(described_class.by_symbol).to eq(
      classes: Lutaml::Lml::UmlClass,
      enums: Lutaml::Lml::Enum,
      data_types: Lutaml::Lml::DataType,
      primitives: Lutaml::Lml::PrimitiveType,
    )
  end

  it 'excludes enums from classifiable types' do
    expect(described_class.classifiable).not_to include(Lutaml::Lml::Enum)
    expect(described_class.classifiable).to include(Lutaml::Lml::UmlClass)
  end

  it 'keeps every entity_type symbol a Document collection reader' do
    doc = Lutaml::Lml::Document.new
    described_class.symbols.each do |symbol|
      expect { doc.public_send(symbol) }.not_to raise_error
    end
  end

  it 'preserves imported primitives through view resolution' do
    dir = Dir.mktmpdir
    model = File.join(dir, 'model.lutaml')
    File.write(model, <<~LML)
      class Foo { }
      primitive Bar
    LML
    view = File.join(dir, 'view.lutaml')
    File.write(view, 'view V { import "model.lutaml" }')

    doc = Lutaml::Lml.parse(File.open(view))
    expect(doc.classes.map(&:name)).to eq(['Foo'])
    expect(doc.primitives.map(&:name)).to eq(['Bar'])
  ensure
    FileUtils.rm_rf(dir)
  end
end
