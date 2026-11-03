# frozen_string_literal: true

require "spec_helper"
require "json"
require "lutaml/model/lml/ordered_content"
require_relative "../../support/lml_order_fixtures"

# lutaml-model#1033 card 02c: per-instance element order as portable data.
RSpec.describe Lutaml::Model::Lml::OrderedContent do
  let(:fx) { LmlOrderFixtures }
  let(:rejected) { Lutaml::Model::Lml::RejectedError }

  def descriptor(klass)
    described_class.descriptor_for(klass, mapping: klass.mappings_for(:xml))
  end

  # Rebuild an instance from member values only (no recorded order).
  def rebuild(klass, source)
    klass.new(klass.attributes.keys.to_h { |k| [k, source.public_send(k)] })
  end

  def json_cycle(tokens)
    JSON.parse(JSON.generate(tokens))
  end

  describe "mixed content round trip" do
    let(:para) { fx::Para.from_xml(fx::PARA_XML) }
    let(:desc) { descriptor(fx::Para) }

    it "captures interleaved elements, text and CDATA as tokens" do
      expect(described_class.capture(desc, para)).to eq(
        [
          { "kind" => "text", "attribute" => "text", "index" => 0 },
          { "kind" => "element", "attribute" => "em", "index" => 0 },
          { "kind" => "text", "attribute" => "text", "index" => 1 },
          { "kind" => "cdata", "literal" => "cd" },
          { "kind" => "text", "attribute" => "text", "index" => 2 },
          { "kind" => "element", "attribute" => "bold", "index" => 0 },
          { "kind" => "element", "attribute" => "em", "index" => 1 },
          { "kind" => "text", "attribute" => "text", "index" => 3 },
          { "kind" => "element", "attribute" => "note", "index" => 0 },
          { "kind" => "text", "attribute" => "text", "index" => 4 },
        ],
      )
    end

    it "reproduces the original document from tokens alone" do
      tokens = json_cycle(described_class.capture(desc, para))
      fresh = rebuild(fx::Para, para)
      expect(fresh.element_order).to be_nil

      described_class.apply(desc, tokens, fresh)

      expect(fresh.to_xml).to eq(para.to_xml)
      expect(fresh.to_xml).to include("<em>a</em> mid")
      expect(fresh.to_xml.index("<b>x</b>")).to be < fresh.to_xml.index("<em>b</em>")
    end

    it "lets tokens, not member grouping, decide interleaving" do
      fresh = rebuild(fx::Para, para)
      described_class.apply(desc, [
                              { "kind" => "element", "attribute" => "note", "index" => 0 },
                              { "kind" => "element", "attribute" => "em", "index" => 0 },
                              { "kind" => "text", "literal" => "-" },
                              { "kind" => "element", "attribute" => "em", "index" => 1 },
                              { "kind" => "element", "attribute" => "bold", "index" => 0 },
                            ], fresh)

      expect(fresh.to_xml).to eq("<p><note>n</note><em>a</em>-<em>b</em><b>x</b></p>")
    end

    it "refuses to apply references that would need the member reordered" do
      fresh = rebuild(fx::Para, para)
      expect do
        described_class.apply(desc, [
                                { "kind" => "element", "attribute" => "em", "index" => 1 },
                                { "kind" => "element", "attribute" => "em", "index" => 0 },
                              ], fresh)
      end.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:invalid_ordered_content)
        expect(e.detail).to include("must ascend")
      }
      expect(fresh.element_order).to be_nil
    end
  end

  describe "element-only ordered models" do
    let(:transport) { fx::Transport.from_xml(fx::TRANSPORT_XML) }
    let(:desc) { descriptor(fx::Transport) }

    it "preserves repeated interleaved elements" do
      tokens = described_class.capture(desc, transport)
      expect(tokens.map { |t| [t["attribute"], t["index"]] }).to eq(
        [["car", 0], ["boat", 0], ["car", 1], ["boat", 1], ["car", 2]],
      )

      fresh = rebuild(fx::Transport, transport)
      described_class.apply(desc, json_cycle(tokens), fresh)
      expect(fresh.to_xml).to eq(transport.to_xml)
    end

    it "ignores indentation between elements" do
      pretty = fx::Transport.from_xml(
        "<transportation>\n  <car>1</car>\n  <boat>2</boat>\n</transportation>",
      )
      expect(described_class.capture(desc, pretty).map { |t| t["kind"] }).to eq(%w[element element])
    end
  end

  describe "namespace identity" do
    let(:ns) { fx::Namespaced.from_xml(fx::NAMESPACED_XML) }
    let(:desc) { descriptor(fx::Namespaced) }

    it "tells same-named elements apart by namespace and restores it" do
      tokens = described_class.capture(desc, ns)
      expect(tokens.map { |t| [t["attribute"], t["index"]] }).to eq(
        [["a_items", 0], ["b_items", 0], ["a_items", 1], ["b_items", 1]],
      )

      fresh = rebuild(fx::Namespaced, ns)
      entries = described_class.apply(desc, json_cycle(tokens), fresh)
      expect(entries.map(&:namespace_uri)).to eq(
        ["urn:lml-order:a", "urn:lml-order:b", "urn:lml-order:a", "urn:lml-order:b"],
      )

      # The serialized form interleaves 1,2,3,4 and puts 2 and 4 in B's namespace.
      xml = fresh.to_xml
      expect(xml.scan(/<item[^>]*>(\d)</).flatten).to eq(%w[1 2 3 4])
      expect(xml.scan(/<item xmlns="urn:lml-order:b">(\d)</).flatten).to eq(%w[2 4])
    end
  end

  describe "instances without a recorded order" do
    it "captures nil and applies nil" do
      desc = descriptor(fx::Transport)
      built = fx::Transport.new(car: %w[1], boat: %w[2])
      expect(described_class.capture(desc, built)).to be_nil
      expect(described_class.apply(desc, nil, built)).to be_nil
    end

    it "appends members added after parsing, in declaration order" do
      desc = descriptor(fx::Transport)
      parsed = fx::Transport.from_xml(fx::TRANSPORT_XML)
      parsed.boat << "6"
      tokens = described_class.capture(desc, parsed)
      expect(tokens.last).to eq("kind" => "element", "attribute" => "boat", "index" => 2)
    end
  end

  describe "rejections" do
    it "refuses a custom-method element rule as imperative order" do
      expect { descriptor(fx::ImperativeRule) }.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:imperative_element_order)
      }
    end

    it "refuses a class that generates its own element_order" do
      expect { descriptor(fx::ImperativeOrder) }.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:imperative_element_order)
        expect(e.detail).to include("element_order")
      }
    end

    it "refuses a source member named __lml_content" do
      expect { descriptor(fx::ReservedMember) }.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:reserved_member)
      }
    end

    it "returns no descriptor for a mapping without per-instance order" do
      expect(descriptor(fx::Plain)).to be_nil
    end

    describe "invalid tokens" do
      let(:desc) { descriptor(fx::Transport) }
      let(:instance) { fx::Transport.new(car: %w[1 2], boat: %w[3]) }

      def reason_of(tokens, instance: nil)
        described_class.validate!(desc, tokens, instance: instance)
        nil
      rescue rejected => e
        [e.reason, e.detail]
      end

      def el(attribute, index)
        { "kind" => "element", "attribute" => attribute, "index" => index }
      end

      it "accepts tokens that reference existing indices" do
        tokens = [el("car", 1), el("boat", 0), el("car", 0)]
        expect(described_class.validate!(desc, tokens, instance: instance).size).to eq(3)
      end

      it "rejects an index past the member's values" do
        reason, detail = reason_of([el("car", 2)], instance: instance)
        expect(reason).to eq(:invalid_ordered_content)
        expect(detail).to include("car[2] does not exist")
      end

      it "rejects duplicate references" do
        reason, detail = reason_of([el("car", 0), el("car", 0)])
        expect(reason).to eq(:invalid_ordered_content)
        expect(detail).to include("duplicate")
      end

      it "rejects unknown members, bad kinds, bad shapes and negative indices" do
        [
          [el("nope", 0)],
          [{ "kind" => "comment", "literal" => "x" }],
          [{ "kind" => "element", "attribute" => "car", "index" => 0, "literal" => "x" }],
          [{ "kind" => "text" }],
          [{ "kind" => "text", "attribute" => "car", "index" => 0 }],
          [el("car", -1)],
          [el("car", "0")],
          ["car"],
        ].each do |tokens|
          expect(reason_of(tokens)&.first).to eq(:invalid_ordered_content), tokens.inspect
        end
      end

      it "rejects a non-zero index on a scalar member" do
        para_desc = descriptor(fx::Para)
        expect do
          described_class.validate!(para_desc, [el("note", 1)])
        end.to raise_error(rejected) { |e| expect(e.detail).to include("only has index 0") }
      end

      it "does not touch the instance when apply fails" do
        before = instance.element_order
        expect { described_class.apply(desc, [el("car", 5)], instance) }.to raise_error(rejected)
        expect(instance.element_order).to eq(before)
      end
    end

    it "refuses comments in element_order rather than dropping them" do
      desc = descriptor(fx::Transport)
      parsed = fx::Transport.from_xml("<transportation><car>1</car><!--c--></transportation>")
      expect { described_class.capture(desc, parsed) }.to raise_error(rejected) { |e|
        expect(e.reason).to eq(:invalid_ordered_content)
      }
    end
  end
end
