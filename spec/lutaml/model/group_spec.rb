require "spec_helper"
require "lutaml/model"

module GroupSpec
  class Ceramic < Lutaml::Model::Serializable
    attribute :type, :string
    attribute :name, :string

    xml do
      no_root
      map_element :type, to: :type
      map_element :name, to: :name
    end
  end

  class CeramicCollection < Lutaml::Model::Serializable
    attribute :ceramic, Ceramic, collection: 1..2

    xml do
      root "collection"
      map_element "ceramic", to: :ceramic
    end
  end

  class AttributeValueType < Lutaml::Model::Type::Decimal
  end

  class GroupOfItems < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :type, :string
    attribute :description, :string
    attribute :code, :string

    xml do
      no_root
      sequence do
        map_element "name", to: :name
        map_element "type", to: :type
        map_element "description", to: :description,
                                   namespace: "http://www.sparxsystems.com/profiles/GML/1.0",
                                   prefix: "GML"
      end
      map_attribute "code", to: :code, namespace: "http://www.example.com", prefix: "ex1"
    end
  end

  class ComplexType < Lutaml::Model::Serializable
    attribute :tag, AttributeValueType
    attribute :content, :string
    attribute :group, :string
    import_model_attributes GroupOfItems

    xml do
      root "GroupOfItems"
      map_attribute "tag", to: :tag
      map_content to: :content
      map_element :group, to: :group
      import_model_mappings GroupOfItems
    end

    key_value do
      map :tag, to: :tag
      map :content, to: :content
      map :group, to: :group
      import_model_mappings GroupOfItems
    end
  end

  class ImportModelWithExistingMappings < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :type, :string

    xml do
      map_attribute :name, to: :name
      map_element :type, to: :type
    end

    key_value do
      map :name, to: :name
      map :type, to: :type
    end

    import_model GroupOfItems
  end

  class SimpleType < Lutaml::Model::Serializable
    import_model GroupOfItems
  end

  class GenericType < Lutaml::Model::Serializable
    import_model_mappings GroupOfItems
  end

  class GroupWithRoot < Lutaml::Model::Serializable
    attribute :name, :string

    xml do
      root "group"
      map_element :name, to: :name
    end
  end

  class ContributionInfo < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :person, :string
      attribute :organization, :string
    end

    xml do
      no_root
      map_element "person", to: :person
      map_element "organization", to: :organization
    end
  end

  class Contributor < Lutaml::Model::Serializable
    choice(min: 1, max: 1) do
      attribute :role, :string
    end

    import_model_attributes ContributionInfo

    xml do
      root "contributor"
      map_element "role", to: :role
      map_element "person", to: :person
      map_element "organization", to: :organization
    end
  end

  class GroupGlaze < Lutaml::Model::Serializable
    choice(min: 1, max: 2) do
      attribute :color, :string
      attribute :temperature, :string
      attribute :food_safe, :boolean
    end

    key_value do
      map "color", to: :color
      map "temperature", to: :temperature
    end
  end

  class GroupCeramic < Lutaml::Model::Serializable
    attribute :role, :string
    import_model_attributes GroupGlaze

    json do
      map "role", to: :role
      map "color", to: :color, render_default: true
      map "temperature", to: :temperature
      import_model_mappings GroupGlaze
    end
  end
end

RSpec.describe "Group" do
  context "with no_root" do
    let(:mapper) { GroupSpec::CeramicCollection }

    it "raises error if root-less class used directly for parsing" do
      xml = <<~XML
        <type>Data</type>
        <name>Smith</name>
      XML

      expect { GroupSpec::Ceramic.from_xml(xml) }.to raise_error(
        Lutaml::Model::NoRootMappingError,
        "GroupSpec::Ceramic has `no_root`, it allowed only for reusable models",
      )
    end

    it "raises error if root_less class used for deserializing" do
      ceramic = GroupSpec::Ceramic.new(type: "Data", name: "Starc")

      expect { ceramic.to_xml }.to raise_error(
        Lutaml::Model::NoRootMappingError,
        "GroupSpec::Ceramic has `no_root`, it allowed only for reusable models",
      )
    end

    it "correctly get the element of root-less class" do
      xml = <<~XML
        <collection>
          <ceramic>
            <type>Data</type>
          </ceramic>
        </collection>
      XML

      expect { mapper.from_xml(xml) }.not_to raise_error
    end
  end

  it "import model attributes for key_value" do
    hash = {
      "color" => "Color",
      "temperature" => "High",
    }

    contrib = GroupSpec::GroupCeramic.from_json(hash.to_json)
    expect(contrib.color).to eq("Color")
    expect(contrib.temperature).to eq("High")
    expect(contrib.role).to be_nil

    serialized = contrib.to_json
    expect(serialized).to eq(hash.to_json)

    expect(contrib.validate).to be_empty
  end

  it "import model attributes for xml having choice block" do
    xml = <<~XML
      <contributor>
        <role>Role</role>
        <person>Person</person>
      </contributor>
    XML

    contrib = GroupSpec::Contributor.from_xml(xml)
    expect(contrib.person).to eq("Person")
    expect(contrib.organization).to be_nil
    expect(contrib.role).to eq("Role")

    serialized = contrib.to_xml
    expect(serialized).to be_equivalent_to(xml)

    expect(contrib.validate).to be_empty
  end

  context "with model" do
    it "import attributes" do
      expect(GroupSpec::ComplexType.attributes).to include(GroupSpec::GroupOfItems.attributes)
    end

    it "import mappings in xml block" do
      expect(GroupSpec::ComplexType.mappings_for(:xml).elements).to include(GroupSpec::GroupOfItems.mappings_for(:xml).elements)
    end

    it "import mappings outside xml block" do
      expect(GroupSpec::GenericType.mappings_for(:xml).elements).to include(GroupSpec::GroupOfItems.mappings_for(:xml).elements)
    end

    it "import attributes and mappings in xml block" do
      expect(GroupSpec::ComplexType.attributes).to include(GroupSpec::GroupOfItems.attributes)
      expect(GroupSpec::ComplexType.mappings_for(:xml).elements).to include(GroupSpec::GroupOfItems.mappings_for(:xml).elements)
    end

    it "import attributes and mappings outside the xml block" do
      expect(GroupSpec::SimpleType.attributes).to include(GroupSpec::GroupOfItems.attributes)
      expect(GroupSpec::SimpleType.mappings_for(:xml).elements).to include(GroupSpec::GroupOfItems.mappings_for(:xml).elements)
    end

    it "imports key_value mappings having default mappings" do
      formats = %i[json yaml toml]

      formats.each do |format|
        expect(GroupSpec::ComplexType.mappings_for(format).mappings)
          .to include(GroupSpec::GroupOfItems.mappings_for(format).mappings)
      end
    end

    it "imports the model with existing the mappings and attributes" do
      expect(GroupSpec::ImportModelWithExistingMappings.attributes).to include(GroupSpec::GroupOfItems.attributes)
      expect(GroupSpec::ImportModelWithExistingMappings.mappings_for(:xml).elements).to include(GroupSpec::GroupOfItems.mappings_for(:xml).elements)
      expect(GroupSpec::ImportModelWithExistingMappings.mappings_for(:xml).attributes).to include(GroupSpec::GroupOfItems.mappings_for(:xml).attributes)

      formats = %i[json yaml toml]
      formats.each do |format|
        expect(GroupSpec::ImportModelWithExistingMappings.mappings_for(format).mappings)
          .to include(GroupSpec::GroupOfItems.mappings_for(format).mappings)
      end
    end

    it "raises error if root is defined on imported class" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          import_model GroupSpec::GroupWithRoot
        end
      end.to raise_error(Lutaml::Model::ImportModelWithRootError, "Cannot import a model `GroupSpec::GroupWithRoot` with a root element")
    end

    it "raises error if namespace is defined with no_root" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          xml do
            no_root
            namespace "http://www.omg.org/spec/XMI/20131001", "xmi"
          end
        end
      end.to raise_error(Lutaml::Model::NoRootNamespaceError, "Cannot assign namespace to `no_root`")
    end
  end
end
