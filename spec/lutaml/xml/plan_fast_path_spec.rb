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

  it "is on by default and can be disabled" do
    expect(Lutaml::Model::Configuration.new.xml_plan_fast_path).to be(true)

    # Opt-out restores the interpretive pipeline for the whole process.
    Lutaml::Model::Config.instance.xml_plan_fast_path = false
    item = item_class.new(id: 1, name: "a", tags: %w[x])
    parsed = root_class.from_xml(root_class.new(item: [item]).to_xml)
    expect(parsed.item.first.id).to eq(1)
  ensure
    Lutaml::Model::Config.instance.xml_plan_fast_path = true
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

  it "defers custom-method rules through fragment interpretation" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :note, :string

      xml do
        element "doc"
        map_element "note", to: :note, with: { from: :note_from }
      end

      def note_from(instance, value)
        instance.note = value.text.upcase
      end
    end

    expect(Lutaml::Xml::PlanCompiler.compile(klass,
                                             Lutaml::Model::Config.default_register)).not_to be_nil
    expect(klass.from_xml("<doc><note>hi</note></doc>").note).to eq("HI")
  end

  it "compiles multiple spellings in interpretive spelling-group order" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :val, :string, collection: true

      xml do
        element "d"
        map_element %w[a b], to: :val
      end
    end

    parsed = klass.from_xml("<d><a>1</a><b>2</b><a>3</a></d>")
    expect(parsed.val).to eq(%w[1 3 2])
  end

  it "compiles multiple collection rows via callback routing" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :xs, :string, collection: true
      attribute :ys, :string, collection: true

      xml do
        element "d"
        map_element "x", to: :xs
        map_element "y", to: :ys
      end
    end

    parsed = klass.from_xml("<d><x>1</x><y>a</y><x>2</x><y>b</y></d>")
    expect(parsed.xs).to eq(%w[1 2])
    expect(parsed.ys).to eq(%w[a b])
  end

  it "splits delimited attributes" do
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :tags, :string, collection: true

      xml do
        element "d"
        map_attribute "tags", to: :tags, delimiter: ","
      end
    end

    expect(klass.from_xml('<d tags="a,b,c"/>').tags).to eq(%w[a b c])
  end

  it "compiles delegate rules with post-instance routing" do
    target = Class.new(Lutaml::Model::Serializable) do
      attribute :note, :string

      xml do
        element "tgt"
        map_element "note", to: :note
      end
    end
    klass = Class.new(Lutaml::Model::Serializable) do
      attribute :tgt, target

      xml do
        element "doc"
        map_element "note", to: :note, delegate: :tgt
      end
    end

    expect(Lutaml::Xml::PlanCompiler.compile(klass,
                                             Lutaml::Model::Config.default_register)).not_to be_nil
    parsed = klass.from_xml("<doc><note>hi</note></doc>")
    expect(parsed.tgt.note).to eq("hi")
  end

  it "routes a single collection row natively (hybrid routing)" do
    plan = Lutaml::Xml::PlanCompiler.compile(
      Class.new(Lutaml::Model::Serializable) do
        attribute :xs, :string, collection: true
        attribute :name, :string

        xml do
          element "d"
          map_element "x", to: :xs
          map_element "name", to: :name
        end
      end,
      Lutaml::Model::Config.default_register,
    )
    expect(plan[:rows].map { |r| r[2] }).to include(:collection_native)
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

  describe "ordered and mixed content" do
    around do |example|
      Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
    end

    let(:emph_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "emph"
          map_content to: :text
        end
      end
    end

    let(:mixed_class) do
      emph = emph_class
      Class.new(Lutaml::Model::Serializable) do
        attribute :emph, emph, collection: true
        attribute :text, :string, collection: true
        attribute :kind, :string

        xml do
          element "para"
          mixed_content
          map_attribute "kind", to: :kind
          map_element "emph", to: :emph
          map_content to: :text
        end
      end
    end

    it "compiles mixed-content mappings and reconstructs element_order" do
      xml = %(<para kind="a">Hi <emph>there</emph> bye</para>)

      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      interpretive = mixed_class.from_xml(xml)
      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      fast = mixed_class.from_xml(xml)

      order_sig = ->(m) do
        m.element_order.map { |e| [e.type, e.name, e.text_content] }
      end
      expect(order_sig.call(fast)).to eq(order_sig.call(interpretive))
      expect(fast.kind).to eq("a")
      expect(fast.text).to eq(interpretive.text)
      expect(fast.emph.map(&:text)).to eq(interpretive.emph.map(&:text))
      expect(fast.to_xml).to eq(interpretive.to_xml)
    end

    it "yields each_mixed_content equal to the interpretive path" do
      xml = %(<para>Hi <emph>there</emph> bye</para>)

      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      interpretive = mixed_class.from_xml(xml)
      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      fast = mixed_class.from_xml(xml)

      sig = ->(m) do
        m.each_mixed_content.map { |i| i.is_a?(String) ? i : i.text }
      end
      expect(sig.call(fast)).to eq(sig.call(interpretive))
    end

    it "defers ordered nested children interpretively while the parent compiles" do
      mixed = mixed_class
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :para, mixed, collection: true

        xml do
          element "doc"
          map_element "title", to: :title
          map_element "para", to: :para
        end
      end
      plan = Lutaml::Xml::PlanCompiler.compile(
        doc_class, Lutaml::Model::Config.default_register
      )
      expect(plan).not_to be_nil
      expect(plan[:rows].map { |r| r[2] }).to include(:ordered_deferred)

      xml = %(<doc><title>T</title><para>Hi <emph>x</emph> bye</para><para>plain</para></doc>)
      parsed = doc_class.from_xml(xml)
      expect(parsed.title).to eq("T")
      para = parsed.para.first
      expect(para.text).to eq(["Hi ", " bye"])
      expect(para.emph.map(&:text)).to eq(["x"])
      expect(para.element_order.map { |e| [e.type, e.name] })
        .to eq([["Text", "text"], ["Element", "emph"], ["Text", "text"]])
      # absent collections materialize as [] (interpretive parity)
      expect(parsed.para.last.emph).to eq([])
    end

    it "reconstructs element_order for ordered-only mappings" do
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :a, :string, collection: true
        attribute :b, :string, collection: true

        xml do
          element "d"
          ordered
          map_element "a", to: :a
          map_element "b", to: :b
        end
      end
      xml = %(<d><a>1</a><b>x</b><a>2</a></d>)

      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      interpretive = klass.from_xml(xml)
      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      fast = klass.from_xml(xml)

      expect(fast.a).to eq(interpretive.a)
      expect(fast.b).to eq(interpretive.b)
      expect(fast.element_order.map { |e| [e.type, e.name] })
        .to eq(interpretive.element_order.map { |e| [e.type, e.name] })
    end

    it "joins content runs for non-collection content attributes" do
      emph = emph_class
      klass = Class.new(Lutaml::Model::Serializable) do
        attribute :emph, emph, collection: true

        xml do
          element "para"
          map_element "emph", to: :emph
        end
      end

      parsed = klass.from_xml(%(<para><emph>bold</emph></para>))
      expect(parsed.emph.first.text).to eq("bold")
    end
  end

  describe "serialize fast path" do
    around do |example|
      Lutaml::Model::Config.with_adapter(xml: :leptris) { example.run }
    end

    it "serializes ordered models byte-equal from element_order" do
      emph = Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "emph"
          map_content to: :text
        end
      end
      para = Class.new(Lutaml::Model::Serializable) do
        attribute :emph, emph, collection: true
        attribute :text, :string, collection: true
        attribute :kind, :string

        xml do
          element "para"
          mixed_content
          map_attribute "kind", to: :kind
          map_element "emph", to: :emph
          map_content to: :text
        end
      end
      doc_class = Class.new(Lutaml::Model::Serializable) do
        attribute :title, :string
        attribute :para, para, collection: true

        xml do
          element "doc"
          map_element "title", to: :title
          map_element "para", to: :para
        end
      end
      xml = %(<doc><title>T</title><para kind="a">Hi <emph>there</emph> bye <emph>again</emph>!</para><para>second</para></doc>)

      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      fast = doc_class.from_xml(xml)
      fast_out = fast.to_xml
      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      interp_out = doc_class.from_xml(xml).to_xml

      expect(fast_out).to eq(interp_out)
      expect(fast_out).to include(%(<para kind="a">Hi <emph>there</emph> bye <emph>again</emph>!</para>))
    end

    it "reflects content mutations through the ordered fast serializer" do
      para = Class.new(Lutaml::Model::Serializable) do
        attribute :emph, :string, collection: true
        attribute :text, :string, collection: true

        xml do
          element "para"
          mixed_content
          map_element "emph", to: :emph
          map_content to: :text
        end
      end
      xml = %(<para>Hi <emph>x</emph> bye</para>)

      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      fast = para.from_xml(xml)
      fast.text = ["MUTATED ", " tail"]
      fast_out = fast.to_xml
      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      interp = para.from_xml(xml)
      interp.text = ["MUTATED ", " tail"]
      expect(fast_out).to eq(interp.to_xml)
      expect(fast_out).to eq("<para>MUTATED <emph>x</emph> tail</para>")
    end

    it "falls back interpretively for ordered instances without element_order" do
      para = Class.new(Lutaml::Model::Serializable) do
        attribute :emph, :string, collection: true
        attribute :text, :string, collection: true

        xml do
          element "para"
          mixed_content
          map_element "emph", to: :emph
          map_content to: :text
        end
      end
      model = para.new(emph: ["z"], text: ["hello ", " world"])

      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      out = model.to_xml
      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      expect(out).to eq(model.to_xml)
      expect(out).to eq("<para>hello <emph>z</emph> world</para>")
    end

    it "serializes byte-equal to the interpretive path" do
      item = Class.new(Lutaml::Model::Serializable) do
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
      root = Class.new(Lutaml::Model::Serializable) do
        attribute :item, item, collection: true

        xml do
          element "root"
          map_element "item", to: :item
        end
      end
      model = root.new(item: [item.new(id: 1, name: "a", tags: %w[x y]),
                              item.new(id: 2, name: "b", tags: %w[z])])

      Lutaml::Model::Config.instance.xml_plan_fast_path = false
      interpretive = model.to_xml
      Lutaml::Model::Config.instance.xml_plan_fast_path = true
      expect(model.to_xml).to eq(interpretive)
    end

    # lutaml-model#88: name-keyed plan rows would hydrate every
    # same-name occurrence into EVERY partition attribute (verified
    # double-capture) — discriminator models must take the interpretive
    # path, and a partitioned CHILD model must opt its parent out too.
    it "falls back to the interpretive path for when_attribute models" do
      component = Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "component"
          map_element "text", to: :text
        end
      end
      stub_const("PlanFastPath::Component", component)

      partitioned = Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, component, collection: true
        attribute :purpose, component, collection: true

        xml do
          element "requirement"
          map_element "component", when_attribute: "type",
                                   to: { "guidance" => :guidance,
                                         "purpose" => :purpose }
        end
      end
      stub_const("PlanFastPath::Partitioned", partitioned)

      req = partitioned.from_xml(<<~XML)
        <requirement>
          <component type="guidance"><text>g1</text></component>
          <component type="purpose"><text>p1</text></component>
          <component type="guidance"><text>g2</text></component>
        </requirement>
      XML

      expect(req.guidance.map(&:text)).to eq(%w[g1 g2])
      expect(req.purpose.map(&:text)).to eq(["p1"])

      expect(Lutaml::Xml::PlanCompiler.compile(partitioned,
                                               :default)).to be_nil
    end

    it "opts a parent out when a child model partitions with when_attribute" do
      component = Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string

        xml do
          element "component"
          map_element "text", to: :text
        end
      end
      inner = Class.new(Lutaml::Model::Serializable) do
        attribute :guidance, component, collection: true

        xml do
          element "req"
          map_element "component", to: :guidance,
                                   when_attribute: { "type" => "guidance" }
        end
      end
      outer = Class.new(Lutaml::Model::Serializable) do
        attribute :req, inner

        xml do
          element "holder"
          map_element "req", to: :req
        end
      end
      stub_const("PlanFastPath::Nested", outer)

      doc = outer.from_xml(
        "<holder><req><component type=\"guidance\"><text>g1</text></component></req></holder>",
      )
      expect(doc.req.guidance.map(&:text)).to eq(["g1"])
    end

    it "round-trips through both fast paths" do
      item = Class.new(Lutaml::Model::Serializable) do
        attribute :id, :integer
        attribute :name, :string

        xml do
          element "item"
          map_attribute "id", to: :id
          map_element "name", to: :name
        end
      end
      root = Class.new(Lutaml::Model::Serializable) do
        attribute :item, item, collection: true

        xml do
          element "root"
          map_element "item", to: :item
        end
      end
      model = root.new(item: [item.new(id: 7, name: "n")])

      xml = model.to_xml
      parsed = root.from_xml(xml)
      expect(parsed.item.first.id).to eq(7)
      expect(parsed.to_xml).to eq(xml)
    end
  end
end
