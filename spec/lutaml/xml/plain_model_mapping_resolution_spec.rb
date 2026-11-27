# frozen_string_literal: true

require "spec_helper"
require "lutaml/model"

# Regression spec (0.8.186, #1212 follow-up): the per-unit namespace
# child-matching added for XmlCompiler-derived models consults
# `session.xml_mapping` while a rule's child candidates are scanned. The
# session's model class may be a PLAIN class (declared via `model
# PlainClass`, e.g. relaton's Bibcollection carried by its
# relaton-collection mapper), and a plain class does not answer
# `mappings_for` — so the unguarded call raised NoMethodError mid-parse
# and every XML parse of such a document failed with
# Lutaml::Model::InvalidFormatError. Observed consumer breakage:
# relaton-cli's XmlToHtmlRenderer suite failed on lutaml-model 0.8.186
# (relaton CI, 2026-11-26).
#
# The fix resolves the session mapping only when the instance is a
# Lutaml::Model::Serialize (XmlCompiler-derived models are Serializable,
# so #1212's namespace matching is unchanged); plain models resolve no
# session mapping and the parse behaves exactly as before 0.8.186.
RSpec.describe "Plain model parse does not resolve the session mapping" do
  let(:plain_collection_class) do
    Class.new do
      attr_accessor :title
    end
  end

  let(:collection_namespace_class) do
    Class.new(Lutaml::Xml::W3c::XmlNamespace) do
      uri "https://example.org/collection"
      prefix_default "c"
      element_form_default :qualified
    end
  end

  let(:mapper_class) do
    pc = plain_collection_class
    ns = collection_namespace_class

    Class.new(Lutaml::Model::Serializable) do
      model pc
      attribute :title, :string

      xml do
        root "collection"
        namespace ns
        map_element "title", to: :title
      end

      def self.name
        "PlainModelCollectionMapper"
      end
    end
  end

  # The child shares the rule's local name but spells a foreign namespace:
  # it misses the exact, alias and prefix branches and reaches the
  # declaring-model-namespace branch added by #1212, which is the call
  # site that resolved the session mapping.
  let(:xml) do
    <<~XML
      <c:collection xmlns:c="#{collection_namespace_class.uri}"
                    xmlns:f="https://example.org/foreign">
        <f:title>alien namespace</f:title>
      </c:collection>
    XML
  end

  it "parses a document whose child shares a rule's local name in a foreign namespace" do
    instance = mapper_class.from_xml(xml)

    expect(instance).to be_a(plain_collection_class)
    expect(instance.title).to be_nil
  end

  it "still binds a rule-spelled child of a plain-model document" do
    xml = <<~XML
      <c:collection xmlns:c="#{collection_namespace_class.uri}">
        <c:title>in namespace</c:title>
      </c:collection>
    XML

    instance = mapper_class.from_xml(xml)

    expect(instance.title).to eq("in namespace")
  end
end
