# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Element visibility modifier' do
  def parse(src)
    Lutaml::Lml.parse_document(StringIO.new(src))
  end

  it 'defaults to public' do
    doc = parse("class Foo { }\n")
    expect(doc.classes.first.visibility).to eq('public')
  end

  %w[public private protected package].each do |level|
    it "parses #{level} on a class" do
      doc = parse("#{level} class Foo { }\n")
      expect(doc.classes.first.visibility).to eq(level)
    end
  end

  it 'parses visibility on enums, data types and package contents' do
    doc = parse(<<~LML)
      private enum Finish { matte }
      protected data_type MyString { }
      package Pkg {
        private class Hidden { }
        public enum Open { a }
      }
    LML
    expect(doc.enums.first.visibility).to eq('private')
    expect(doc.data_types.first.visibility).to eq('protected')
    expect(doc.packages.first.classes.first.visibility).to eq('private')
    expect(doc.packages.first.enums.first.visibility).to eq('public')
  end

  it 'combines with the abstract/interface modifier' do
    doc = parse("private abstract class Base { }\n")
    expect(doc.classes.first.visibility).to eq('private')
    expect(doc.classes.first.modifier).to eq('abstract')
  end

  it 'binds `package class` as a package-visible class, not a package named class' do
    doc = parse("package class Foo { }\n")
    expect(doc.packages).to be_empty
    expect(doc.classes.first.name).to eq('Foo')
    expect(doc.classes.first.visibility).to eq('package')
  end

  describe 'canonical in-block declarations (par. Declaration modifiers)' do
    it 'sets visibility from the block declaration' do
      doc = parse(<<~LML)
        class Glaze {
          visibility private
          attribute color, String
        }
      LML
      expect(doc.classes.first.visibility).to eq('private')
    end

    it 'maps abstract true/false onto is_abstract' do
      doc = parse(<<~LML)
        class Base { abstract true }
        class Leaf { abstract false }
      LML
      expect(doc.classes.first.is_abstract).to be(true)
      expect(doc.classes.last.is_abstract).to be(false)
    end

    it 'applies to enum bodies' do
      doc = parse("enum Finish {\n  visibility protected\n  matte\n}\n")
      expect(doc.enums.first.visibility).to eq('protected')
    end

    it 'applies to data_type bodies' do
      doc = parse("data_type MyString {\n  visibility private\n}\n")
      expect(doc.data_types.first.visibility).to eq('private')
    end

    it 'expands the abstract prefix to the canonical declaration' do
      doc = parse("abstract class Base { }\n")
      expect(doc.classes.first.is_abstract).to be(true)
      expect(doc.classes.first.modifier).to eq('abstract')
    end
  end

  describe 'visibility inside models blocks' do
    %w[public private protected package].each do |level|
      it "parses #{level} on a class inside models" do
        doc = parse("models P {\n  #{level} class C { attribute a, String }\n}\n")
        expect(doc.classes.first.visibility).to eq(level)
      end
    end

    it 'parses all visibility levels on class/enum/data_type inside models' do
      doc = parse(<<~LML)
        models P {
          private class Hidden { }
          public enum Open { a }
          protected data_type Safe { }
        }
      LML
      expect(doc.classes.first.visibility).to eq('private')
      expect(doc.enums.first.visibility).to eq('public')
      expect(doc.data_types.first.visibility).to eq('protected')
    end

    it 'combines with abstract modifier inside models' do
      doc = parse("models P {\n  private abstract class Base { }\n}\n")
      expect(doc.classes.first.visibility).to eq('private')
      expect(doc.classes.first.modifier).to eq('abstract')
    end
  end

  describe 'package visibility' do
    it 'parses visibility on package declarations' do
      doc = parse("private package Ceramics {\n  class Tile { }\n}\n")
      expect(doc.packages.first.visibility).to eq('private')
      expect(doc.packages.first.classes.first.name).to eq('Tile')
    end

    it 'keeps bare package declarations binding as packages' do
      doc = parse("package Ceramics {\n  class Tile { }\n}\n")
      expect(doc.packages.first.name).to eq('Ceramics')
      expect(doc.packages.first.classes.first.name).to eq('Tile')
    end
  end
end
