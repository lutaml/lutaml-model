# frozen_string_literal: true

require "spec_helper"

# lutaml/lutaml-model#1224: the moxml lane in adapter selection —
# detection already delegates to moxml ("the authority on XML adapter
# availability"), but selection could not express the facade lane:
# no :moxml type, a registration-snapshot default, and no unset-pin
# API. The three asks:
#
# 1. a :moxml adapter type — resolution defers the ENGINE to moxml at
#    parse time (the engine stays a deployment decision owned by
#    moxml),
# 2. the xml lane's metadata default is the deferred lane,
# 3. Config.unset_adapter_type restores auto-detection, so a
#    consumer can undo another gem's process-wide pin through a
#    supported call.
RSpec.describe "the moxml lane in adapter selection (#1224)" do
  # the #1212 probe shape: cross-namespace child binding is the
  # tightest "does this selection parse correctly" signal
  let(:s1_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example/s1"
      prefix_default "s1"
    end
  end

  let(:s2_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example/s2"
      prefix_default "s2"
    end
  end

  let(:bound_class) do
    ns2 = s2_ns
    Class.new(Lutaml::Model::Serializable) do
      attribute :lower, Lutaml::Model::Type::String
      xml do
        element "bound"
        namespace ns2
        map_element "lower", to: :lower
      end
    end
  end

  let(:wrapper_class) do
    ns1 = s1_ns
    bound = bound_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :ref, Lutaml::Model::Type::String
      attribute :bound, bound
      xml do
        element "wrapper"
        namespace ns1
        map_attribute "ref", to: :ref
        map_element "bound", to: :bound
      end
    end
  end

  let(:instance_xml) do
    '<s1:wrapper xmlns:s1="http://example/s1" xmlns:s2="http://example/s2" ref="r1"><s2:bound><s2:lower>0</s2:lower></s2:bound></s1:wrapper>'
  end

  after do
    # restore the spec_helper default for every later example
    Lutaml::Model::Config.xml_adapter_type = :nokogiri
  end

  describe "the :moxml adapter type" do
    it "validates as a selectable xml adapter type" do
      expect { Lutaml::Model::AdapterResolver.resolved_adapter_class(:xml, :moxml) }
        .not_to raise_error
    end

    it "parses through the deferred engine and binds namespaced children" do
      Lutaml::Model::Config.xml_adapter_type = :moxml

      parsed = wrapper_class.from_xml(instance_xml)
      expect(parsed.ref).to eq("r1")
      expect(parsed.bound&.lower).to eq("0")
    end

    it "resolves lazily - the deferrer class stands in and the engine answers at call time" do
      adapter = Lutaml::Model::AdapterResolver.resolved_adapter_class(
        :xml, :moxml
      )

      # the class IS the deferrer; the engine resolves per call
      expect(adapter.name).to eq("Lutaml::Xml::Adapter::MoxmlAdapter")
      expect(adapter).to respond_to(:parse)
      expect(adapter.moxml_adapter_class.name)
        .to match(/Leptris|Nokogiri/)
    end
  end

  describe "the unset-pin API" do
    it "restores auto-detection after a pin" do
      Lutaml::Model::Config.xml_adapter_type = :ox
      expect(Lutaml::Model::Config.xml_adapter_type).to eq(:ox)

      Lutaml::Model::Config.unset_adapter_type(:xml)

      # the pin is gone: configured answers nil and the resolution
      # ladder re-runs (detection delegates to moxml s runtime engine)
      expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
      expect(Lutaml::Model::AdapterResolver.adapter_for(:xml))
        .to respond_to(:parse)
    end
  end
end
