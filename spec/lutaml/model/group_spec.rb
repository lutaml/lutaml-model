require "spec_helper"
require "lutaml/model"

module GroupAttribute
  class FullNameType < Lutaml::Model::Serializable
    attribute :foo, :string

    group do
      attribute :prefix, :string
      attribute :forename, :string
      attribute :formatted, :string
      attribute :surname, :string
      attribute :addition, :string
    end

    attribute :joo, :string

    json do
      map 'jbar', to: :foo
      map 'joo', to: :joo
      map 'jprefix', to: :prefix
      map 'jforename', to: :forename
      map 'jformatted', to: :formatted
      map 'jsurname', to: :surname
      map 'jaddition', to: :addition
    end
  end
end

RSpec.describe GroupAttribute do
  let(:mapper) { GroupAttribute::FullNameType }

  context 'with JSON mapping' do
    let(:json) do
      <<~DOC.gsub(/\n\z/, '')
        {
          "jbar": "foo",
          "joo": "joo",
          "jprefix": "prefix",
          "jaddition": "addition"
        }
      DOC
    end

    describe '.from_json' do
      it 'maps JSON to object' do
        instance = mapper.from_json(json)
        expect(instance.foo).to eq('foo')
        expect(instance.joo).to eq('joo')
        expect(instance.prefix).to eq('prefix')
        expect(instance.addition).to eq('addition')
      end
    end

    describe '.to_json' do
      it 'converts objects to JSON' do
        instance = mapper.new(foo: 'foo', joo: 'joo', prefix: 'prefix', addition: 'addition')
        instance.validate!
        result = instance.to_json(pretty: true)
        expect(result).to eq(json)
      end
    end
  end
end
