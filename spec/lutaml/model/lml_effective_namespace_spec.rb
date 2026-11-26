# frozen_string_literal: true

require "lutaml/model"
require "nokogiri"
require_relative "../../fixtures/lml_effective_namespace/models"

# The exported XML rule namespace must be the namespace Ruby's serializer
# really gives that member (lutaml-model#1033; Ruby is canonical).
RSpec.describe "LML effective XML namespaces" do
  let(:fx) { LmlEffectiveNamespaceFixtures }
  let(:lml) { Lutaml::Model::Lml }
  let(:registry) do
    lml::ValueDeclarations.new({
                                 Lutaml::Xml::W3c::XmlIdType => { "base" => "string", "facets" => {} },
                                 fx::OtherNsType => { "base" => "string", "facets" => {} },
                               })
  end
  let(:xml_ns) { "http://www.w3.org/XML/1998/namespace" }

  def rules_of(klass)
    bundle = lml.export_bundle(klass, value_declarations: registry)
    bundle.models.fetch("#{klass.name}@default")["mappings"]["xml"]["rules"]
      .to_h { |rule| [rule["name"].first, rule] }
  end

  def root_namespace(klass)
    klass.mappings_for(:xml).namespace_uri
  end

  # name => namespace URI ("" for none), as Ruby really serializes the sample.
  def serialized(klass)
    root = Nokogiri::XML(fx::SAMPLES.fetch(klass).call.to_xml).root
    elements = root.element_children.to_h { |e| [e.name, e.namespace&.href.to_s] }
    attributes = root.attribute_nodes.to_h { |a| [a.name, a.namespace&.href.to_s] }
    [elements, attributes]
  end

  # The namespace URI a projected rule claims, given the owning model's namespace.
  def claimed(rule, owner_uri)
    case rule["namespace"]["mode"]
    when "uri" then rule["namespace"]["uri"]
    when "unqualified" then ""
    else rule["kind"] == "attribute" ? "" : owner_uri.to_s
    end
  end

  def self.agrees_with_the_serializer(klass_name)
    it "projects #{klass_name} rules with the namespace Ruby serializes" do
      klass = fx.const_get(klass_name)
      elements, attributes = serialized(klass)
      rules = rules_of(klass)
      expect(rules).not_to be_empty
      rules.each_value do |rule|
        actual = (rule["kind"] == "attribute" ? attributes : elements).fetch(rule["name"].first)
        # A model-typed member (leaf) is named by its own mapping, not the rule.
        next if rule["to"] == "leaf"

        expect(claimed(rule, root_namespace(klass))).to eq(actual), "#{rule['name'].first}: #{rule['namespace']}"
      end
    end
  end

  %w[Host QualifiedHost AttrQualifiedHost NoNamespace].each { |name| agrees_with_the_serializer(name) }

  describe "the stated modes" do
    let(:host) { rules_of(fx::Host) }

    it "states the real xml namespace and prefix of an attribute whose TYPE has one (xml:id)" do
      expect(host["id"]["namespace"]).to eq("mode" => "uri", "uri" => xml_ns, "prefix" => "xml")
    end

    it "states a type-level namespace on an element and attribute without naming any model" do
      expect(host["typedElement"]["namespace"]).to eq("mode" => "uri", "uri" => "urn:lml:other", "prefix" => "o")
      expect(host["typedAttribute"]["namespace"]).to eq("mode" => "uri", "uri" => "urn:lml:other", "prefix" => "o")
    end

    it "resolves a plain string element of a namespaced model to unqualified (not inherit)" do
      expect(host["plain"]["namespace"]).to eq("mode" => "unqualified")
    end

    it "states explicit opt-outs as unqualified and form: :qualified as inherit" do
      expect(host["optedOut"]["namespace"]).to eq("mode" => "unqualified")
      expect(host["flat"]["namespace"]).to eq("mode" => "unqualified")
      expect(host["forced"]["namespace"]).to eq("mode" => "inherit")
    end

    it "keeps a plain attribute and a model-typed member at inherit" do
      expect(host["plainAttribute"]["namespace"]).to eq("mode" => "inherit")
      expect(host["leaf"]["namespace"]).to eq("mode" => "inherit")
    end

    it "follows the namespace's element_form_default and attribute_form_default" do
      qualified = rules_of(fx::QualifiedHost)
      expect(qualified["plain"]["namespace"]).to eq("mode" => "inherit")
      expect(qualified["flat"]["namespace"]).to eq("mode" => "unqualified")
      expect(qualified["attr"]["namespace"]).to eq("mode" => "inherit")
      expect(rules_of(fx::AttrQualifiedHost)["attr"]["namespace"])
        .to eq("mode" => "uri", "uri" => "urn:lml:attrq", "prefix" => "a")
    end

    it "leaves a model with no namespace entirely at inherit (builtin behavior unchanged)" do
      expect(rules_of(fx::NoNamespace).values.map { |r| r["namespace"] }.uniq).to eq([{ "mode" => "inherit" }])
    end
  end

  it "is unaffected by a registry for models that use no custom type" do
    expect(lml.export_bundle(fx::NoNamespace).models.keys).to eq(["#{fx::NoNamespace.name}@default"])
  end
end
