# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Class operations' do
  def parse(src)
    Lutaml::Lml.parse_document(StringIO.new(src))
  end

  let(:doc) do
    parse(<<~LML)
      class Ceramic {
        + getGlazeType(glazeCode: CharacterString = "123"): GlazeType[1..*] {ordered, unique, query}
        - simpleOp(): String
        op2()
        multi(a: String, b: Integer = 5, in c: Boolean)
      }
    LML
  end

  it 'parses operations onto the class' do
    ops = doc.classes.first.operations
    expect(ops.map(&:name)).to eq(%w[getGlazeType simpleOp op2 multi])
  end

  it 'maps symbol visibility prefixes' do
    ops = doc.classes.first.operations
    expect(ops.map(&:visibility)).to eq(%w[public private public public])
  end

  it 'captures the return type and property list' do
    op = doc.classes.first.operations.first
    expect(op.return_type).to eq('GlazeType')
    expect(op.stereotype).to eq(%w[ordered unique query])
  end

  it 'captures parameters with types, defaults and directions' do
    op = doc.classes.first.operations.first
    expect(op.owned_parameter.map(&:name)).to eq(['glazeCode'])
    expect(op.owned_parameter.first.type).to eq('CharacterString')
    expect(op.owned_parameter.first.default).to eq('123')
    multi = doc.classes.first.operations.last
    expect(multi.owned_parameter.map { |p| [p.name, p.type, p.default, p.direction] })
      .to eq([['a', 'String', nil, 'in'],
              ['b', 'Integer', '5', 'in'],
              ['c', 'Boolean', nil, 'in']])
  end

  it 'coexists with attributes in one class body' do
    doc = parse(<<~LML)
      class Widget {
        attribute code, String
        + calc(x: Integer): Integer
      }
    LML
    expect(doc.classes.first.attributes.map(&:name)).to eq(['code'])
    expect(doc.classes.first.operations.map(&:name)).to eq(['calc'])
  end
end
