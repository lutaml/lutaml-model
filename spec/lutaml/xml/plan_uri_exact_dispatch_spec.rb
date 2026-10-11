# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan fast path: (URI, local) dispatch and W3C xml:* attributes" do
  # Same-name element rows in different namespaces must dispatch by
  # the child type's exact URI — the interpretive matcher's
  # typed-element identity. The w14/w15 docId shape (OOXML
  # settings.xml) collapsed to name-only binding: one row captured
  # both elements and the other stayed empty, so round-trips lost a
  # docId and downstream reconcilers regenerated it.
  let(:w14_ns_class) do
    klass = Class.new(Lutaml::Xml::Namespace) do
      uri "http://schemas.microsoft.com/office/word/2010/wordml"
      prefix_default "w14"
      attribute_form_default :qualified
    end
    stub_const("PlanUriLocal::W14Ns", klass)
    klass
  end

  let(:w15_ns_class) do
    klass = Class.new(Lutaml::Xml::Namespace) do
      uri "http://schemas.microsoft.com/office/word/2012/wordml"
      prefix_default "w15"
      attribute_form_default :qualified
    end
    stub_const("PlanUriLocal::W15Ns", klass)
    klass
  end

  let(:w_ns_class) do
    klass = Class.new(Lutaml::Xml::Namespace) do
      uri "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      prefix_default "w"
    end
    stub_const("PlanUriLocal::WNs", klass)
    klass
  end

  let(:w14_doc_id_class) do
    w14_ns_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :val, :string

      xml do
        element "docId"
        namespace PlanUriLocal::W14Ns
        map_attribute "val", to: :val
      end
    end
    stub_const("PlanUriLocal::W14DocId", klass)
    klass
  end

  let(:w15_doc_id_class) do
    w15_ns_class
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :val, :string

      xml do
        element "docId"
        namespace PlanUriLocal::W15Ns
        map_attribute "val", to: :val
      end
    end
    stub_const("PlanUriLocal::W15DocId", klass)
    klass
  end

  def define_settings_class
    w_ns_class
    w14_doc_id_class
    w15_doc_id_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :w14_doc_id, PlanUriLocal::W14DocId
      attribute :w15_doc_id, PlanUriLocal::W15DocId

      xml do
        element "settings"
        namespace PlanUriLocal::WNs
        namespace_scope [
          { namespace: PlanUriLocal::W14Ns, declare: :always },
          { namespace: PlanUriLocal::W15Ns, declare: :always },
        ]
        map_element "docId", to: :w14_doc_id, render_nil: false
        map_element "docId", to: :w15_doc_id, render_nil: false
      end
    end
  end

  def settings_xml(body)
    "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" " \
      "xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" " \
      "xmlns:w15=\"http://schemas.microsoft.com/office/word/2012/wordml\">#{body}</w:settings>"
  end

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  it "binds same-name rows by exact URI regardless of document order" do
    settings_class = define_settings_class

    [%(<w14:docId w14:val="{A}"/><w15:docId w15:val="{B}"/>),
     %(<w15:docId w15:val="{B}"/><w14:docId w14:val="{A}"/>)].each do |body|
      settings = settings_class.from_xml(settings_xml(body))

      expect(settings.w14_doc_id&.val).to eq("{A}")
      expect(settings.w15_doc_id&.val).to eq("{B}")
    end
  end

  it "leaves the absent-namespace row unset for single-docId documents" do
    settings_class = define_settings_class

    only_w14 = settings_class.from_xml(
      settings_xml(%(<w14:docId w14:val="{A}"/>)),
    )
    expect(only_w14.w14_doc_id&.val).to eq("{A}")
    expect(only_w14.w15_doc_id).to be_nil

    only_w15 = settings_class.from_xml(
      settings_xml(%(<w15:docId w15:val="{B}"/>)),
    )
    expect(only_w15.w14_doc_id).to be_nil
    expect(only_w15.w15_doc_id&.val).to eq("{B}")
  end

  it "emits each docId under its own namespace on serialize" do
    settings_class = define_settings_class
    settings = settings_class.from_xml(
      settings_xml(%(<w14:docId w14:val="{A}"/><w15:docId w15:val="{B}"/>)),
    )

    output = settings.to_xml
    expect(output).to include("<w14:docId w14:val=\"{A}\"/>")
    expect(output).to include("<w15:docId w15:val=\"{B}\"/>")
  end

  # The xml prefix is implicit (W3C-reserved): xml:* attribute rules
  # bind by raw name and must not be qualified under the model's
  # namespace by attribute form defaults (w:t's xml:space under a
  # :qualified WML mapping dropped the attribute entirely).
  it "round-trips xml:space through the plan lane" do
    w_ns_class
    text_class = Class.new(Lutaml::Model::Serializable) do
      attribute :content, :string
      attribute :xml_space, :string

      xml do
        element "t"
        namespace PlanUriLocal::WNs
        map_content to: :content
        map_attribute "xml:space", to: :xml_space
      end
    end
    stub_const("PlanUriLocal::Text", text_class)

    source = '<w:t xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" ' \
             'xml:space="preserve">hi </w:t>'
    text = text_class.from_xml(source)

    expect(text.xml_space).to eq("preserve")
    expect(text.content).to eq("hi ")
    expect(text.to_xml).to include('xml:space="preserve"')
  end

  # Writer-added values sit outside the parse-built element_order.
  # The ordered serialize lane reconciles them at the interpretive
  # anchors — but only for instances a writer has touched; pristine
  # parsed instances skip the reconciliation scan entirely.
  it "emits writer-added children after parse and skips the scan when pristine" do
    w_ns_class
    w14_doc_id_class
    zoom_class = Class.new(Lutaml::Model::Serializable) do
      attribute :percent, :string

      xml do
        element "zoom"
        namespace PlanUriLocal::WNs
        map_attribute "percent", to: :percent
      end
    end
    stub_const("PlanUriLocal::Zoom", zoom_class)
    settings_class = Class.new(Lutaml::Model::Serializable) do
      attribute :zoom, PlanUriLocal::Zoom
      attribute :w14_doc_id, PlanUriLocal::W14DocId

      xml do
        element "settings"
        namespace PlanUriLocal::WNs
        map_element "zoom", to: :zoom
        map_element "docId", to: :w14_doc_id
      end
    end
    stub_const("PlanUriLocal::Settings", settings_class)

    source = settings_xml(%(<w:zoom w:percent="100"/>))
    pristine = settings_class.from_xml(source)
    expect(pristine.zoom.percent).to eq("100")
    expect(pristine.to_xml).not_to include("docId")

    mutated = settings_class.from_xml(source)
    mutated.w14_doc_id = w14_doc_id_class.new(val: "{A}")
    output = mutated.to_xml
    expect(output).to include("<docId")
    expect(output).to include('val="{A}"')
    expect(output.index("zoom")).to be < output.index("docId")
  end

  # Root declaration-plan parity: plan-hydrated roots carry the same
  # import_declaration_plan state the interpretive parse records, so
  # consumers and the interpretive serialize fallback see in-scope
  # declarations (#872).
  it "records the source declaration plan on plan-hydrated roots" do
    settings_class = define_settings_class
    settings = settings_class.from_xml(
      settings_xml(%(<w14:docId w14:val="{A}"/>)),
    )

    plan = settings.import_declaration_plan
    expect(plan).to be_a(Lutaml::Xml::DeclarationPlan)
    hoisted = plan.root_node.hoisted_declarations
    expect(hoisted["w14"]).to eq("http://schemas.microsoft.com/office/word/2010/wordml")

    skipped = settings_class.from_xml(
      settings_xml(%(<w14:docId w14:val="{A}"/>)),
      import_declaration_plan: :skip,
    )
    expect(skipped.import_declaration_plan).to be_nil
  end
end
