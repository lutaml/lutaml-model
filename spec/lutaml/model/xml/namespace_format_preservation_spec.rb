# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace format preservation" do
  let(:test_namespace) do
    Class.new(Lutaml::Model::Xml::Namespace) do
      uri "http://test.com"
      prefix_default "test"
    end
  end

  let(:model_class) do
    ns = test_namespace
    Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      
      xml do
        root "TestModel"
        namespace ns
        map_element "name", to: :name
      end
    end
  end

  describe "default format round-trip" do
    let(:xml) { '<TestModel xmlns="http://test.com"><name>Test</name></TestModel>' }
    
    it "preserves default format on serialization" do
      model = model_class.from_xml(xml)
      output = model.to_xml
      
      expect(output).to include('xmlns="http://test.com"')
      expect(output).not_to include('xmlns:test=')
    end
  end

  describe "prefix format round-trip" do
    let(:xml) { '<test:TestModel xmlns:test="http://test.com"><test:name>Test</test:name></test:TestModel>' }
    
    it "preserves prefix format on serialization" do
      model = model_class.from_xml(xml)
      output = model.to_xml
      
      expect(output).to include('xmlns:test="http://test.com"')
      expect(output).not_to include('xmlns="http://test.com"')
    end
  end
end
