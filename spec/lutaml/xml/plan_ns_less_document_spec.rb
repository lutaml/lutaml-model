# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan fast path: namespace-less models on namespaced documents" do
  # lutaml-model#932: elements (unlike attributes) inherit the default
  # xmlns, so the walk's strict no-URI default dropped every child of a
  # namespaced document for models that declare no namespace. The
  # ns_lenient flag restores the interpretive matcher's behavior:
  # children match by local name under any document qualification.

  let(:child_class) do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :fileref, :string

      xml do
        element "imagedata"
        map_attribute "fileref", to: :fileref
      end
    end
    stub_const("NsLessDoc::Imagedata", klass)
    klass
  end

  def define_parent
    child_class
    Class.new(Lutaml::Model::Serializable) do
      attribute :imagedata, NsLessDoc::Imagedata
      attribute :content, :string, collection: true

      xml do
        element "imageobject"
        map_element "imagedata", to: :imagedata
        map_content to: :content
      end
    end
    
  end

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  it "binds nested children under a default namespace" do
    parent = define_parent
    doc = '<imageobject xmlns="http://docbook.org/ns/docbook">' \
          '<imagedata fileref="x.png"/></imageobject>' 

    expect(parent.from_xml(doc).imagedata.fileref).to eq("x.png")
  end

  it "binds nested children under a prefixed namespace" do
    parent = define_parent
    doc = '<db:imageobject xmlns:db="http://docbook.org/ns/docbook">' \
          '<db:imagedata fileref="x.png"/></db:imageobject>' 

    expect(parent.from_xml(doc).imagedata.fileref).to eq("x.png")
  end

  it "keeps binding on namespace-less documents" do
    parent = define_parent
    doc = %(<imageobject><imagedata fileref="x.png"/></imageobject>)

    expect(parent.from_xml(doc).imagedata.fileref).to eq("x.png")
  end

  it "binds nested children of mixed-content models under a default namespace" do
    parent = define_parent
    parent.xml do
      element "imageobject"
      mixed_content
      map_content to: :content
      map_element "imagedata", to: :imagedata
    end
    doc = '<imageobject xmlns="http://docbook.org/ns/docbook">' \
          'text<imagedata fileref="x.png"/>tail</imageobject>' 

    parsed = parent.from_xml(doc)
    expect(parsed.imagedata.fileref).to eq("x.png")
    expect(parsed.content).to include("text")
  end
end
