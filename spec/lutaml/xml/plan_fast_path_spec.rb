# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML plan fast path" do
  let(:classes) do
    item_class = Class.new(Lutaml::Model::Serializable) do
      attribute :id, :integer
      attribute :name, :string
      attribute :tags, :string, collection: true

      xml do
        element "item"
        map_attribute "id", to: :id
        map_element "name", to: :name
        map_element "tag", to: :tags
      end
    end
    root_class = Class.new(Lutaml::Model::Serializable) do
      attribute :item, item_class, collection: true

      xml do
        element "root"
        map_element "item", to: :item
      end
    end
    [item_class, root_class]
  end

  let(:item_class) { classes[0] }
  let(:root_class) { classes[1] }

  around do |example|
    old = Lutaml::Model::Config.instance.xml_plan_fast_path
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
    example.run
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = old
  end

  it "is opt-in and off by default" do
    expect(Lutaml::Model::Configuration.new.xml_plan_fast_path).to be(false)
  end

  it "hydrates equal to the interpretive path" do
    xml = root_class.new(item: [
                           item_class.new(id: 1, name: "a", tags: %w[x y]),
                           item_class.new(id: 2, name: "b", tags: %w[z]),
                         ]).to_xml

    expect(root_class.from_xml(xml).item).to eq(root_class.new(item: [
                                                                 item_class.new(id: 1, name: "a", tags: %w[x y]),
                                                                 item_class.new(id: 2, name: "b", tags: %w[z]),
                                                               ]).item)
  end

  it "matches the interpretive path on missing elements" do
    xml = <<~XML
      <root>
        <item id="1"><name>A</name><tag>x</tag></item>
        <item id="2"><tag>y</tag><tag>z</tag></item>
        <item id="3"><name>C</name></item>
      </root>
    XML

    parsed = root_class.from_xml(xml)
    expect(parsed.item.map { |i| [i.id, i.name, i.tags] })
      .to eq([[1, "A", %w[x]], [2, nil, %w[y z]], [3, "C", []]])
  end

  it "wraps engine parse errors as InvalidFormatError" do
    Lutaml::Model::Config.with_adapter(xml: :leptris) do
      expect { root_class.from_xml("<root><item>") }
        .to raise_error(Lutaml::Model::InvalidFormatError)
    end
  end

  it "falls back for non-compilable models" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :note, :string

      xml do
        element "doc"
        map_element "note", to: :note, with: { from: :note_from }
      end

      def note_from(instance, value)
        instance.note = value.text
      end
    end

    expect(Lutaml::Xml::PlanCompiler.compile(klass,
                                             Lutaml::Model::Config.default_register)).to be_nil
    expect(klass.from_xml("<doc><note>hi</note></doc>").note).to eq("hi")
  end

  describe "newly compilable shapes" do
    around do |example|
      Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
    end

    it "compiles namespace-qualified models and matches any bound prefix" do
      ns = Class.new(Lutaml::Xml::W3c::XmlNamespace) do
        uri "urn:probe"
        prefix_default "p"
        element_form_default :qualified
      end
      item = Class.new(Lutaml::Model::Serializable) do
        attribute :name, :string
        xml do
          namespace ns
          element "item"
          map_element "name", to: :name
        end
      end
      root = Class.new(Lutaml::Model::Serializable) do
        attribute :item, item, collection: true
        xml do
          namespace ns
          element "root"
          map_element "item", to: :item
        end
      end
      xml = %(<zz:root xmlns:zz="urn:probe"><zz:item><zz:name>A</zz:name></zz:item></zz:root>)

      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      ref = root.from_xml(xml)
      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      fast = root.from_xml(xml)
      expect(fast.item.map(&:name)).to eq(ref.item.map(&:name))
    end

    it "reads cdata sections as text" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :t, :string
        xml do
          element "d"
          map_element "t", to: :t, cdata: true
        end
      end
      expect(klass.from_xml("<d><t><![CDATA[a <b> c]]></t></d>").t).to eq("a <b> c")
    end

    it "captures raw element subtrees verbatim" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :frag, :string
        xml do
          element "d"
          map_element "frag", to: :frag, raw: :element
        end
      end
      # Verbatim capture: the fast path returns the exact source
      # subtree (the interpretive path re-serializes with indentation).
      expect(klass.from_xml(%(<d><frag><x a="1">inner</x></frag></d>)).frag)
        .to eq(%(<frag><x a="1">inner</x></frag>))
    end

    it "hydrates content runs on collection attributes" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string, collection: true
        attribute :b, :string
        xml do
          element "p"
          map_content to: :text
          map_element "b", to: :b
        end
      end
      parsed = klass.from_xml("<p>Hello <b>bold</b> world!</p>")
      expect(parsed.text).to eq(["Hello ", " world!"])
      expect(parsed.b).to eq("bold")
    end
  end
end
