require "spec_helper"
require_relative "../../../lib/lutaml/model"

# NOTE: FPIs in namespace positions are INVALID XML per W3C specification.
# XML namespaces must be valid URIs. FPIs like "-//OASIS//DTD..." are NOT valid URIs.
# When parsing XML with FPI namespaces, we convert them to RFC 3151 URN format
# on serialization. TRUE ROUND-TRIP IS NOT POSSIBLE since the original is invalid.

RSpec.describe "FPI Namespace Handling" do
  context "with Nokogiri adapter" do
    before(:all) do
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    it "converts FPI namespace to URN on serialization" do
      # XML with FPI as namespace URI (INVALID but parseable)
      xml = <<~XML
        <table xmlns="-//OASIS//DTD XML Exchange Table Model 19990315//EN">
          <entry>Data</entry>
        </table>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)

      # Serialization converts FPI to RFC 3151 URN
      output = doc.to_xml

      # The FPI is converted to a valid URN - round-trip is NOT possible
      # since the original FPI namespace is invalid XML
      expect(output).to include("urn:publicid:-//OASIS//DTD+XML+Exchange+Table+Model+19990315//EN")
      expect(output).not_to include('xmlns="-//OASIS//DTD')
    end

    it "converts +// FPI namespace to URN on serialization" do
      xml = <<~XML
        <item xmlns="+//Example//DTD Test 2000//EN">
          <name>Test</name>
        </item>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)

      output = doc.to_xml

      expect(output).to include("urn:publicid:+//Example//DTD+Test+2000//EN")
    end
  end

  context "with Ox adapter" do
    before(:all) do
      Lutaml::Model::Config.xml_adapter_type = :ox
    end

    it "converts FPI namespace to URN on serialization" do
      xml = <<~XML
        <table xmlns="-//OASIS//DTD XML Exchange Table Model 19990315//EN">
          <entry>Data</entry>
        </table>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)

      output = doc.to_xml

      expect(output).to include("urn:publicid:-//OASIS//DTD+XML+Exchange+Table+Model+19990315//EN")
    end
  end

  context "with Oga adapter" do
    before(:all) do
      Lutaml::Model::Config.xml_adapter_type = :oga
    end

    it "converts FPI namespace to URN on serialization" do
      xml = <<~XML
        <table xmlns="-//OASIS//DTD XML Exchange Table Model 19990315//EN">
          <entry>Data</entry>
        </table>
      XML

      adapter_class = Lutaml::Model::Config.xml_adapter
      doc = adapter_class.parse(xml)

      output = doc.to_xml

      expect(output).to include("urn:publicid:-//OASIS//DTD+XML+Exchange+Table+Model+19990315//EN")
    end
  end

  context "helper methods in BaseAdapter" do
    before(:all) do
      # Use any adapter to test the class methods
      Lutaml::Model::Config.xml_adapter_type = :nokogiri
    end

    let(:adapter_class) { Lutaml::Model::Config.xml_adapter }

    describe ".fpi?" do
      it "returns true for FPI starting with -//" do
        expect(adapter_class.fpi?("-//OASIS//DTD XML Exchange Table Model 19990315//EN")).to be true
      end

      it "returns true for FPI starting with +//" do
        expect(adapter_class.fpi?("+//Example//DTD Test 2000//EN")).to be true
      end

      it "returns false for valid URI" do
        expect(adapter_class.fpi?("http://example.com/namespace")).to be false
      end

      it "returns false for URN" do
        expect(adapter_class.fpi?("urn:publicid:-//OASIS//DTD+XML+Exchange+Table+Model+19990315//EN")).to be false
      end

      it "returns false for nil" do
        expect(adapter_class.fpi?(nil)).to be false
      end
    end

    describe ".fpi_to_urn" do
      it "converts -// FPI to URN correctly per RFC 3151" do
        fpi = "-//OASIS//DTD XML Exchange Table Model 19990315//EN"
        expected_urn = "urn:publicid:-//OASIS//DTD+XML+Exchange+Table+Model+19990315//EN"
        expect(adapter_class.fpi_to_urn(fpi)).to eq(expected_urn)
      end

      it "converts +// FPI to URN correctly per RFC 3151" do
        fpi = "+//Example//DTD Test 2000//EN"
        expected_urn = "urn:publicid:+//Example//DTD+Test+2000//EN"
        expect(adapter_class.fpi_to_urn(fpi)).to eq(expected_urn)
      end

      it "returns nil for valid URI" do
        expect(adapter_class.fpi_to_urn("http://example.com/namespace")).to be_nil
      end

      it "returns nil for nil input" do
        expect(adapter_class.fpi_to_urn(nil)).to be_nil
      end
    end
  end
end
