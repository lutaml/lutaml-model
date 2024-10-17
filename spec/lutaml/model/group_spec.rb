require "spec_helper"
require "lutaml/model"

module GroupBlock
  class GroupElement < Lutaml::Model::Serializable
    attribute :foo, :string
    attribute :joo, :string
    attribute :one, :string
    attribute :two, :string
    attribute :three, :string

    json do
      map 'jbar', to: :foo
      group from: :attrs_from_dict, to: :attrs_to_dict do
        map 'one'
        map 'two'
      end
      map 'joo', to: :joo
      group from: :other_attrs_from_dict, to: :other_attrs_to_dict do
        map 'three'
      end
    end

    yaml do
      map 'ybar', to: :foo
      group from: :attrs_from_dict, to: :attrs_to_dict do
        map 'one'
        map 'two'
      end
    end

    toml do
      map 'tbar', to: :foo
      group from: :attrs_from_dict, to: :attrs_to_dict do
        map 'one'
        map 'two'
      end
    end

    # xml do
    #   root 'hlo'
    #   map_element 'xbar', to: :foo
    #   group from: :attrs_from_xml, to: :attrs_to_xml do
    #     map_element 'one'
    #     map_attribute 'two'
    #     map_content
    #   end
    # end

    def attrs_from_dict(model, value)
      model.one = value['one']
      model.two = value['two']
    end

    def attrs_to_dict(model, doc)
      doc['one'] = model.one
      doc['two'] = model.two
    end

    def other_attrs_from_dict(model, value)
      model.three = value['three']
    end

    def other_attrs_to_dict(model, doc)
      doc['three'] = model.three
    end

    def attrs_from_xml(model, value)
      model.one = value[:elements]['one'].text
      model.two = value[:attributes]['two']
      model.three = value[:content].text
    end

    def attrs_to_xml(model, element, doc)
      doc.add_attribute(element, 'two', model.two)
      doc.add_text(element, model.three)

      one = doc.create_element('one')
      doc.add_text(one, model.one)
      doc.add_element(element, one)
    end
  end
end

RSpec.describe GroupBlock do
  let(:mapper) { GroupBlock::GroupElement }

  context 'with JSON mapping' do
    let(:json) do
      <<~DOC.gsub(/\n\z/, '')
        {
          "one": "one",
          "two": "two",
          "three": "three"
        }
      DOC
    end

    describe '.from_json' do
      it 'maps JSON to object' do
        instance = mapper.from_json(json)
        expect(instance.one).to eq('one')
        expect(instance.two).to eq('two')
      end
    end

    describe '.to_json' do
      it 'converts objects to JSON' do
        instance = mapper.new(one: 'one', two: 'two', three: 'three')

        result = instance.to_json(pretty: true)
        expect(result).to eq(json)
      end
    end
  end
end
