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
      map 'joo', to: :joo
      group from: :other_attrs_from_dict, to: :other_attrs_to_dict do
        map 'three'
      end
    end

    toml do
      map 'tbar', to: :foo
      group from: :attrs_from_dict, to: :attrs_to_dict do
        map 'one'
        map 'two'
      end
      map 'joo', to: :joo
      group from: :other_attrs_from_dict, to: :other_attrs_to_dict do
        map 'three'
      end
    end

    # xml do
    #   root 'hlo'
    #   map_element 'xbar', to: :foo
    #   group from: :attrs_from_xml, to: :attrs_to_xml do
    #     map_element 'one', namespace: "http:www.techie.com", prefix: "foo"
    #     map_attribute 'two', namesapce: "http:www.minions.com", prefix: "bar"
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
          "two": "two"
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
        instance = mapper.new(one: 'one', two: 'two')

        result = instance.to_json(pretty: true)
        expect(result).to eq(json)
      end
    end
  end

  context 'with YAML mapping' do
    let(:yaml) do
      <<~DOC
        ---
        one: one
        two: two
      DOC
    end

    describe '.from_yaml' do
      it 'maps YAML to object' do
        instance = mapper.from_yaml(yaml)

        expect(instance.one).to eq('one')
        expect(instance.two).to eq('two')
      end
    end

    describe '.to_yaml' do
      it 'converts objects to YAML' do
        instance = mapper.new(one: 'one', two: 'two')

        result = instance.to_yaml
        expect(result).to eq(yaml)
      end
    end
  end

  context 'with TOML mapping' do
    let(:toml) do
      <<~DOC
        one = "one"
        two = "two"
      DOC
    end

    describe '.from_toml' do
      it 'maps TOML to object' do
        instance = mapper.from_toml(toml)

        expect(instance.one).to eq('one')
        expect(instance.two).to eq('two')
      end
    end

    describe '.to_toml' do
      it 'converts objects to TOML' do
        instance = mapper.new(one: 'one', two: 'two')

        result = instance.to_toml
        expect(result).to eq(toml)
      end
    end
  end

  # context 'with XML mapping' do
  #   let(:xml) do
  #     <<~DOC
  #       <el two="two">three<one>one</one></el>
  #     DOC
  #   end

  #   describe '.from_xml' do
  #     it 'maps XML to object' do
  #       instance = mapper.from_xml(xml)

  #       expect(instance.one).to eq('one')
  #       expect(instance.two).to eq('two')
  #       expect(instance.three).to eq('three')
  #     end
  #   end

  #   describe '.to_xml' do
  #     it 'converts objects to XML' do
  #       instance = mapper.new(one: 'one', two: 'two', three: 'three')

  #       result = instance.to_xml

  #       expect(result).to eq('<el two="two">three<one>one</one></el>')
  #     end
  #   end
  # end
end
