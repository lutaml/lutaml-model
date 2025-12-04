# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Force Prefixed Namespace" do
  let(:vcard_ns) do
    Class.new(Lutaml::Model::XmlNamespace) do
      uri "urn:ietf:params:xml:ns:vcard-4.0"
      prefix_default "vcard"
      element_form_default :qualified
    end
  end

  let(:name_model) do
    ns = vcard_ns
    Class.new(Lutaml::Model::Serializable) do
      attribute :given, :string

      xml do
        namespace ns
        root "n"
        map_element "given", to: :given
      end
    end
  end

  let(:vcard_model) do
    ns = vcard_ns
    name_m = name_model

    Class.new(Lutaml::Model::Serializable) do
      attribute :name, name_m

      xml do
        namespace ns
        root "vCard"
        map_element "n", to: :name
      end
    end
  end

  let(:instance) do
    vcard_model.new(name: name_model.new(given: "John"))
  end

  context "default behavior (no prefix: option)" do
    it "uses default namespace for single namespace without attributes" do
      xml = instance.to_xml

      # Own namespace uses default (cleaner)
      expect(xml).to include('xmlns="urn:ietf:params:xml:ns:vcard-4.0"')
      expect(xml).not_to include("xmlns:vcard=")

      # Root element unprefixed
      expect(xml).to include("<vCard")
      expect(xml).not_to include("<vcard:vCard")

      # Child elements inherit default
      expect(xml).to include("<n>")
      expect(xml).to include("<given>")
    end
  end

  context "with prefix: true (forced)" do
    it "uses prefixed namespace even when default would work" do
      xml = instance.to_xml(prefix: true)

      # Own namespace uses prefix (forced by option)
      expect(xml).not_to include('xmlns="urn:ietf:params:xml:ns:vcard-4.0"')
      expect(xml).to include('xmlns:vcard="urn:ietf:params:xml:ns:vcard-4.0"')

      # Root element uses prefix
      expect(xml).to include("<vcard:vCard")
      expect(xml).not_to include("<vCard xmlns")

      # Child elements match parent's prefix format
      expect(xml).to include("<vcard:n>")
      expect(xml).to include("<vcard:given>")
    end
  end

  context "with prefix: false (explicit default)" do
    it "uses default namespace" do
      xml = instance.to_xml(prefix: false)

      # Explicitly request default
      expect(xml).to include('xmlns="urn:ietf:params:xml:ns:vcard-4.0"')
      expect(xml).not_to include("xmlns:vcard=")

      expect(xml).to include("<vCard xmlns")
      expect(xml).to include("<n>")
    end
  end

  context "with prefix: custom string" do
    it "uses custom prefix instead of default" do
      xml = instance.to_xml(prefix: "v")

      # Custom prefix overrides default
      expect(xml).to include('xmlns:v="urn:ietf:params:xml:ns:vcard-4.0"')
      expect(xml).not_to include("xmlns:vcard=")

      expect(xml).to include("<v:vCard")
      expect(xml).to include("<v:n>")
      expect(xml).to include("<v:given>")
    end
  end
end
