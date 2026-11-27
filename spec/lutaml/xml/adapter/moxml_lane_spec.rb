# frozen_string_literal: true

require "spec_helper"

# lutaml/lutaml-model#1224: the moxml lane in adapter selection.
# Detection has always delegated to moxml ("moxml is the authority on
# XML adapter availability"), but selection could not express that
# lane: no :moxml type in the registered snapshot, a registration-time
# engine snapshot as the default, and no supported way to unset a
# process-wide pin. This spec locks the three asks:
#
# 1. a :moxml adapter type — the facade lane: the ENGINE resolves at
#    call time from Moxml::Config, so the engine stays a deployment
#    decision owned by moxml,
# 2. the xml metadata default is the deferred lane, not an engine
#    snapshot,
# 3. Config.unset_adapter_type restores auto-detection, undoing
#    another gem's process-wide pin.
RSpec.describe "the moxml lane in adapter selection (#1224)" do
  # The #1212 probe shape: cross-namespace child binding is the
  # tightest "does this selection parse correctly" signal.
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
    '<s1:wrapper xmlns:s1="http://example/s1" xmlns:s2="http://example/s2" ' \
      'ref="r1"><s2:bound><s2:lower>0</s2:lower></s2:bound></s1:wrapper>'
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

    it "is registered in the format's available snapshot" do
      expect(Lutaml::Model::AdapterResolver.configured_type(:xml)).to eq(:nokogiri)

      options = Lutaml::Model::FormatRegistry.adapter_options_for(:xml)
      expect(options[:available]).to include(:moxml)
    end

    it "resolves to the facade class, whose engine answers at call time" do
      adapter = Lutaml::Model::AdapterResolver.resolved_adapter_class(:xml, :moxml)

      # the resolved class IS the deferrer, not a frozen engine
      expect(adapter.name).to eq("Lutaml::Xml::Adapter::MoxmlAdapter")

      # the engine it defers to is moxml's authority answer
      engine = Moxml::Config.default_adapter
      expect(adapter.resolved_adapter.name)
        .to eq("Lutaml::Xml::Adapter::#{engine.to_s.capitalize}Adapter")
      expect(adapter.moxml_adapter_class.name)
        .to eq("Moxml::Adapter::#{engine.to_s.capitalize}")
    end

    it "parses through the deferred engine and binds namespaced children" do
      Lutaml::Model::Config.xml_adapter_type = :moxml

      parsed = wrapper_class.from_xml(instance_xml)
      expect(parsed.ref).to eq("r1")
      expect(parsed.bound&.lower).to eq("0")
    end

    it "serializes through the deferred engine and round-trips" do
      Lutaml::Model::Config.xml_adapter_type = :moxml

      parsed = wrapper_class.from_xml(instance_xml)
      rendered = parsed.to_xml
      reparsed = wrapper_class.from_xml(rendered)

      expect(reparsed.ref).to eq("r1")
      expect(reparsed.bound&.lower).to eq("0")
    end

    it "is expressible through the block-scoped override" do
      Lutaml::Model::Config.with_adapter(xml: :moxml) do
        parsed = wrapper_class.from_xml(instance_xml)
        expect(parsed.bound&.lower).to eq("0")
      end
    end
  end

  describe "the deferred default" do
    it "registers the metadata default as the deferred lane, not an engine snapshot" do
      options = Lutaml::Model::FormatRegistry.adapter_options_for(:xml)
      expect(options[:default]).to eq(:moxml)
    end
  end

  describe "the unset-pin API" do
    it "restores auto-detection after a process-wide pin" do
      Lutaml::Model::Config.xml_adapter_type = :ox
      expect(Lutaml::Model::Config.xml_adapter_type).to eq(:ox)

      Lutaml::Model::Config.unset_adapter_type(:xml)

      # the pin is gone: the configured type answers nil and the
      # resolution ladder re-runs (detection delegates to moxml's
      # runtime engine)
      expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
      expect(Lutaml::Model::AdapterResolver.adapter_for(:xml))
        .to respond_to(:parse)
    end

    it "is exposed per format through the generated accessor" do
      Lutaml::Model::Config.xml_adapter_type = :ox

      Lutaml::Model::Config.unset_xml_adapter_type

      expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
      expect(Lutaml::Model::Config.xml_adapter).to respond_to(:parse)
    end

    it "drops the detection caches so the ladder re-runs" do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
      expect(Lutaml::Model::AdapterResolver.adapter_for(:xml)).not_to be_nil

      Lutaml::Model::Config.unset_adapter_type(:xml)

      # after the drop, resolution re-detects: the configured slot
      # stays nil and the next resolve lands on a working adapter
      expect(Lutaml::Model::Config.xml_adapter_type).to be_nil
      expect(Lutaml::Model::AdapterResolver.adapter_for(:xml))
        .to respond_to(:parse)
    end
  end
end
