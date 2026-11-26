# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# XmlCompiler-derived models bind one schema namespace at the model
# level while children legally live in the imported schemas'
# namespaces. Every adapter must bind such cross-namespace children
# identically (#1212).
ADAPTERS = %w[default nokogiri].freeze

RSpec.describe "adapter parity for cross-namespace child binding (#1212)" do
  let(:base_xsd) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 targetNamespace="http://example.com/p1212-base"
                 elementFormDefault="qualified">
        <xs:complexType name="Upper">
          <xs:simpleContent>
            <xs:extension base="xs:string"/>
          </xs:simpleContent>
        </xs:complexType>
        <xs:complexType name="Limit">
          <xs:sequence>
            <xs:element name="lower" type="xs:string"/>
            <xs:element name="upper" type="Upper"/>
          </xs:sequence>
        </xs:complexType>
      </xs:schema>
    XSD
  end

  let(:main_xsd) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                 xmlns:b="http://example.com/p1212-base"
                 targetNamespace="http://example.com/p1212-main"
                 elementFormDefault="qualified">
        <xs:import namespace="http://example.com/p1212-base"
                   schemaLocation="base.xsd"/>
        <xs:complexType name="Holder">
          <xs:sequence>
            <xs:element name="limit" type="b:Limit"/>
          </xs:sequence>
        </xs:complexType>
        <xs:element name="root">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="holder" type="Holder"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  let(:instance_xml) do
    <<~XML
      <m:root xmlns:m="http://example.com/p1212-main"
              xmlns:b="http://example.com/p1212-base">
        <m:holder>
          <m:limit>
            <b:lower>0</b:lower>
            <b:upper>5</b:upper>
          </m:limit>
        </m:holder>
      </m:root>
    XML
  end

  ADAPTERS.each do |adapter|
    it "binds imported-schema children on the #{adapter} lane" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "base.xsd"), base_xsd)
        File.write(File.join(dir, "main.xsd"), main_xsd)
        File.write(File.join(dir, "instance.xml"), instance_xml)

        configure = if adapter == "default"
                      ""
                    else
                      "Lutaml::Model::Config.configure do |c|\n  " \
                        "c.xml_adapter_type = :#{adapter}\n" \
                        "end\n"
                    end

        probe = <<~RUBY
          require "lutaml/model"
          #{configure}
          Lutaml::Model::Schema.from_xml(
            File.read("#{dir}/main.xsd"),
            output_dir: "#{dir}/p1212_models",
            load_classes: true,
            namespace: "http://example.com/p1212-main",
            module_namespace: "P1212Models",
            register_id: "p1212_reg",
            location: "#{dir}/main.xsd",
          )
          parsed = Object.const_get("P1212Models::CTRoot").from_xml(
            File.read("#{dir}/instance.xml"),
          )
          limit = parsed.holder.limit
          puts "lower=\#{limit.lower.inspect}"
          puts "upper=\#{limit.upper&.content.inspect}"
        RUBY

        _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", "lib",
                                                 "-e", probe)
        expect(status).to be_success, stderr

        expect(_stdout).to include('lower="0"')
        expect(_stdout).to include('upper="5"')
      end
    end
  end
end
