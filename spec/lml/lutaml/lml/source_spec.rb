# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Lutaml::Lml::Source do
  describe '.wrap' do
    it 'passes through an existing Source' do
      source = described_class.wrap('text')
      expect(described_class.wrap(source)).to equal(source)
    end

    it 'wraps other input kinds' do
      expect(described_class.wrap(StringIO.new('x'))).to be_a(described_class)
    end
  end

  describe '#read' do
    it 'returns a String input directly' do
      expect(described_class.new('literal text').read).to eq('literal text')
    end

    it 'rewinds and reads an IO' do
      io = StringIO.new("diagram Test\nend")
      io.read
      expect(described_class.new(io).read).to eq("diagram Test\nend")
    end

    it 'is repeatable on the same StringIO' do
      source = described_class.new(StringIO.new('abc'))
      expect(source.read).to eq('abc')
      expect(source.read).to eq('abc')
    end
  end

  describe '#path' do
    it 'returns the path for a File' do
      file = Tempfile.new(%w[test .lutaml])
      source = described_class.new(file)
      expect(source.path).to eq(file.path)
      file.close!
    end

    it 'returns nil for anonymous input' do
      expect(described_class.new(StringIO.new('x')).path).to be_nil
      expect(described_class.new('x').path).to be_nil
    end
  end

  describe '#base_dir' do
    it 'is the dirname of the path for files' do
      file = Tempfile.new(%w[test .lutaml])
      source = described_class.new(file)
      expect(source.base_dir).to eq(File.dirname(file.path))
      file.close!
    end

    it 'falls back to the working directory for anonymous input' do
      expect(described_class.new(StringIO.new('x')).base_dir).to eq(Dir.pwd)
    end
  end
end
