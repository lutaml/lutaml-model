require "spec_helper"

RSpec.describe "Reused Elements with Imported Mappings" do
  # Define namespace
  class TestNamespace < Lutaml::Model::XmlNamespace
    uri "http://example.com/test"
    prefix_default "t"
  end

  # Shared child model
  class SharedChild < Lutaml::Model::Serializable
    xml do
      element "child"
      namespace TestNamespace
    end
  end

  # Importable group with child
  class SharedGroup < Lutaml::Model::Serializable
    attribute :child, SharedChild

    xml do
      no_root
      map_element "child", to: :child
    end
  end

  before do
    register = Lutaml::Model::Register.new(:test_register)
    Lutaml::Model::GlobalRegister.register(register)
    register.register_model(SharedGroup, id: :shared_group)
    Lutaml::Model::Config.default_register = :test_register
  end

  # Parent using imported mappings
  class Parent < Lutaml::Model::Serializable
    import_model_attributes :shared_group

    xml do
      element "parent"
      namespace TestNamespace
      import_model_mappings :shared_group
    end
  end

  # Container with two instances of Parent
  class Container < Lutaml::Model::Serializable
    attribute :first, Parent
    attribute :second, Parent

    xml do
      element "container"
      namespace TestNamespace
      map_element "first", to: :first
      map_element "second", to: :second
    end
  end

  it "maintains namespace prefix for all instances" do
    xml = <<~XML
      <t:container xmlns:t="http://example.com/test">
        <t:first><t:child/></t:first>
        <t:second><t:child/></t:second>
      </t:container>
    XML

    instance = Container.from_xml(xml)
    output = instance.to_xml(prefix: "t")

    # Both should have t: prefix
    # Use regex to handle whitespace variations
    expect(output).to match(/<t:first>\s*<t:child\/>/m)
    expect(output).to match(/<t:second>\s*<t:child\/>/m)

    # Should NOT have unprefixed <child/> in second element
    expect(output).not_to match(/<t:second>\s*<child\/>/m)
  end
end