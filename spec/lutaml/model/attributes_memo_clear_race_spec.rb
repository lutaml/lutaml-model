# frozen_string_literal: true

require "spec_helper"

# lutaml-model#815: standalone `SomeModel.new.to_xml` crashed on 0.8.42 when
# the model's attributes are merged through register records whose imports
# clear @merged_attributes_cache re-entrantly from inside ensure_imports! —
# the memo store was materialized before ensure_imports! and the write after
# it hit nil[].
RSpec.describe "attributes memo across import-triggered cache clears" do
  let(:namespace_class) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "https://example.com/ns815"
    end
  end

  let(:register) do
    Lutaml::Model::Register.new(:attrs815, fallback: [:default]).tap do |reg|
      reg.bind_namespace(namespace_class)
    end
  end

  let(:base_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :shared, :string

      xml do
        element "Base815"
        namespace namespace_class
        map_element "shared", to: :shared
      end
    end
  end

  let(:consumer_model) do
    Class.new(Lutaml::Model::Serializable) do
      attribute :own, :string

      xml do
        element "Consumer815"
        namespace namespace_class
        map_element "own", to: :own
      end
    end
  end

  before do
    stub_const("Attrs815::NamespaceClass", namespace_class)
    Lutaml::Model::GlobalContext.reset!
    Lutaml::Model::GlobalRegister.instance.register(register)
    # Populate @register_records through the import the parse path uses.
    base_model.import_model_attributes(consumer_model, register.id)
  end

  after do
    Lutaml::Model::GlobalContext.reset!
  end

  it "serializes a register-bound model as its own document root" do
    instance = base_model.new(shared: "x")
    expect(instance.to_xml).to include("<shared>x</shared>")
  end

  it "merges register attributes after an import-triggered cache clear" do
    instance = consumer_model.new(own: "y")
    expect(instance.to_xml).to include("<own>y</own>")
  end

  it "keeps answering attributes() from the memo after imports" do
    first = consumer_model.attributes(:attrs815)
    expect(consumer_model.attributes(:attrs815)).to equal(first)
  end

  it "survives a re-entrant cache clear from inside ensure_imports!" do
    # uniword's register-bound models (#815): choice/restrict resolution
    # runs clear_cache while ensure_imports! is still on the stack, which
    # nils @merged_attributes_cache after the reader materialized it.
    reentrant = Class.new(base_model) do
      def self.finalized? = true

      def self.ensure_format_mapping_imports!(_register = nil)
        clear_cache
        super
      end
    end

    expect { reentrant.attributes(:attrs815) }.not_to raise_error
    expect(reentrant.attributes(:attrs815)[:shared].name).to eq(:shared)
  end
end
