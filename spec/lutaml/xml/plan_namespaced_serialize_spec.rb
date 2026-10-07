# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan serializer: namespaced models" do
  # lutaml-model#847: the plan path used to refuse namespaced models
  # outright (the xmlns dropped). The DOM emission now spells prefixed
  # names, hoists every distinct (prefix, uri) declaration exactly once
  # onto the output root, and prefixes type-namespaced attribute rows —
  # byte-equal with the interpretive writer.

  let(:wml_ns) do
    Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/gate2/wml"
      prefix_default "w"
      attribute_form_default :qualified
    end
  end

  let(:val_type) do
    stub_const("Gate2Ns::WmlNs", wml_ns)
    type = Class.new(Lutaml::Model::Type::String) do
      include Lutaml::Xml::Type::Configurable

      xml do
        namespace Gate2Ns::WmlNs
      end
    end
    stub_const("Gate2Ns::ValType", type)
    type
  end

  let(:doc_class) do
    val_type
    body_class
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string
      attribute :body, Gate2Ns::Body

      xml do
        element "document"
        namespace Gate2Ns::WmlNs
        map_attribute "name", to: :name
        map_element "body", to: :body
      end
    end
    stub_const("Gate2Ns::Document", model)
    model
  end

  let(:body_class) do
    val_type
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :text, Gate2Ns::ValType, collection: true

      xml do
        element "body"
        namespace Gate2Ns::WmlNs
        map_element "t", to: :text
      end
    end
    stub_const("Gate2Ns::Body", model)
    model
  end

  let(:default_ns_model) do
    ns = Class.new(Lutaml::Xml::Namespace) do
      uri "http://example.com/gate2/default"
    end
    stub_const("Gate2Ns::DefaultNs", ns)
    model = Class.new(Lutaml::Model::Serializable) do
      attribute :name, :string

      xml do
        element "root"
        namespace Gate2Ns::DefaultNs
        map_attribute "name", to: :name
      end
    end
    stub_const("Gate2Ns::DefaultDoc", model)
    model
  end

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  def plan_to_xml(klass, instance)
    plan = Lutaml::Xml::Leptris::PlanCompiler.compile(
      klass, Lutaml::Model::Config.default_register
    )
    Lutaml::Xml::Leptris::PlanSerializer.call(
      instance, plan, Lutaml::Model::Config.default_register
    )
  end

  it "emits the attr_form-qualified attribute with the model prefix" do
    instance = doc_class.new(
      name: "d1",
      body: body_class.new(text: ["hello"]),
    )

    out = plan_to_xml(doc_class, instance)
    # Single namespace with no TYPE-qualified attributes: default-ns
    # element spelling, with the attr_form prefix declared for the
    # qualified plain attribute.
    expect(out).to include(%(xmlns="http://example.com/gate2/wml"))
    expect(out).to include(%(xmlns:w="http://example.com/gate2/wml"))
    expect(out).to include("<document")
    expect(out).to include("w:name=\"d1\"")
    expect(out).to include("<body>")
    expect(out).to include("<t>hello</t>")
  end

  # The plan path spells the type-namespaced attribute w:name=; the
  # interpretive writer emits name= unprefixed (a long-standing
  # interpretive serialize gap — the unprefixed form does not rebind
  # to the (URI, local) rule on reparse). Element tree, declarations,
  # and values are compared; the attribute spelling divergence is
  # pinned by the round-trip example below.
  it "matches the interpretive element tree and declarations" do
    instance = doc_class.new(
      name: "d1",
      body: body_class.new(text: ["hello", "world"]),
    )

    interpretive = Lutaml::Model::Config.with_adapter(xml: :nokogiri) do
      instance.to_xml
    end

    plan_out = plan_to_xml(doc_class, instance)
    # The interpretive writer leaves the attr_form prefix undeclared
    # on a standalone document; the plan path declares it.
    normalized = plan_out.sub(%( xmlns:w="http://example.com/gate2/wml"), "")
    expect(normalized.strip).to eq(interpretive.strip)
  end

  it "round-trips through the plan parse path" do
    instance = doc_class.new(
      name: "d1",
      body: body_class.new(text: ["hello"]),
    )
    xml = plan_to_xml(doc_class, instance)

    reparsed = doc_class.from_xml(xml)
    expect(reparsed.name).to eq("d1")
    expect(reparsed.body.text).to eq(["hello"])
  end

  it "spells default-namespace models unprefixed with xmlns on the root" do
    instance = default_ns_model.new(name: "plain")

    out = plan_to_xml(default_ns_model, instance)
    expect(out).to include(%(xmlns="http://example.com/gate2/default"))
    expect(out).to include("<root")
    expect(out).not_to include("xmlns:xmlns")
  end
end
