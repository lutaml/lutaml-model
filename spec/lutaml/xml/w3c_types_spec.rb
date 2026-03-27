# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Lutaml::Xml::W3c do
  describe "XML Namespace Types" do
    describe Lutaml::Xml::W3c::XmlSpaceType do
      describe ".cast" do
        it "returns 'preserve' for valid value 'preserve'" do
          expect(described_class.cast("preserve")).to eq("preserve")
        end

        it "returns 'default' for valid value 'default'" do
          expect(described_class.cast("default")).to eq("default")
        end

        it "returns nil when value is nil" do
          expect(described_class.cast(nil)).to be_nil
        end

        it "raises ArgumentError for invalid value" do
          expect { described_class.cast("invalid") }.to raise_error(
            ArgumentError,
            "xml:space must be 'default' or 'preserve'",
          )
        end

        it "raises ArgumentError for empty string" do
          expect { described_class.cast("") }.to raise_error(
            ArgumentError,
            "xml:space must be 'default' or 'preserve'",
          )
        end

        it "raises ArgumentError for mixed case values" do
          expect { described_class.cast("PRESERVE") }.to raise_error(
            ArgumentError,
            "xml:space must be 'default' or 'preserve'",
          )
        end
      end
    end
  end

  describe "XSI Namespace Types" do
    describe Lutaml::Xml::W3c::XsiNil do
      describe ".cast" do
        it "returns 'true' for valid value 'true'" do
          expect(described_class.cast("true")).to eq("true")
        end

        it "returns 'false' for valid value 'false'" do
          expect(described_class.cast("false")).to eq("false")
        end

        it "returns nil when value is nil" do
          expect(described_class.cast(nil)).to be_nil
        end

        it "raises ArgumentError for invalid value" do
          expect { described_class.cast("yes") }.to raise_error(
            ArgumentError,
            "xsi:nil must be 'true' or 'false'",
          )
        end

        it "raises ArgumentError for empty string" do
          expect { described_class.cast("") }.to raise_error(
            ArgumentError,
            "xsi:nil must be 'true' or 'false'",
          )
        end

        it "raises ArgumentError for mixed case values" do
          expect { described_class.cast("TRUE") }.to raise_error(
            ArgumentError,
            "xsi:nil must be 'true' or 'false'",
          )
          expect { described_class.cast("False") }.to raise_error(
            ArgumentError,
            "xsi:nil must be 'true' or 'false'",
          )
        end
      end
    end
  end

  describe "XLink Namespace Types" do
    describe Lutaml::Xml::W3c::XlinkTypeAttrType do
      describe ".cast" do
        %w[simple extended locator arc resource title].each do |valid|
          it "returns '#{valid}' for valid value '#{valid}'" do
            expect(described_class.cast(valid)).to eq(valid)
          end
        end

        it "returns nil when value is nil" do
          expect(described_class.cast(nil)).to be_nil
        end

        it "raises ArgumentError for invalid value" do
          expect { described_class.cast("invalid") }.to raise_error(
            ArgumentError,
            "xlink:type must be one of: simple, extended, locator, arc, resource, title",
          )
        end

        it "raises ArgumentError for empty string" do
          expect { described_class.cast("") }.to raise_error(
            ArgumentError,
            "xlink:type must be one of: simple, extended, locator, arc, resource, title",
          )
        end
      end
    end

    describe Lutaml::Xml::W3c::XlinkShowType do
      describe ".cast" do
        %w[new replace embed other none].each do |valid|
          it "returns '#{valid}' for valid value '#{valid}'" do
            expect(described_class.cast(valid)).to eq(valid)
          end
        end

        it "returns nil when value is nil" do
          expect(described_class.cast(nil)).to be_nil
        end

        it "raises ArgumentError for invalid value" do
          expect { described_class.cast("invalid") }.to raise_error(
            ArgumentError,
            "xlink:show must be one of: new, replace, embed, other, none",
          )
        end

        it "raises ArgumentError for empty string" do
          expect { described_class.cast("") }.to raise_error(
            ArgumentError,
            "xlink:show must be one of: new, replace, embed, other, none",
          )
        end
      end
    end

    describe Lutaml::Xml::W3c::XlinkActuateType do
      describe ".cast" do
        %w[onLoad onRequest other none].each do |valid|
          it "returns '#{valid}' for valid value '#{valid}'" do
            expect(described_class.cast(valid)).to eq(valid)
          end
        end

        it "returns nil when value is nil" do
          expect(described_class.cast(nil)).to be_nil
        end

        it "raises ArgumentError for invalid value" do
          expect { described_class.cast("invalid") }.to raise_error(
            ArgumentError,
            "xlink:actuate must be one of: onLoad, onRequest, other, none",
          )
        end

        it "raises ArgumentError for empty string" do
          expect { described_class.cast("") }.to raise_error(
            ArgumentError,
            "xlink:actuate must be one of: onLoad, onRequest, other, none",
          )
        end
      end
    end
  end

  describe "Symbol Registration" do
    before do
      # Force loading of W3c module and registration of all types
      described_class.register_types!
    end

    describe "XML types registered" do
      it "registers :xml_lang" do
        expect(Lutaml::Model::Type.lookup(:xml_lang))
          .to eq(Lutaml::Xml::W3c::XmlLangType)
      end

      it "registers :xml_space" do
        expect(Lutaml::Model::Type.lookup(:xml_space))
          .to eq(Lutaml::Xml::W3c::XmlSpaceType)
      end

      it "registers :xml_base" do
        expect(Lutaml::Model::Type.lookup(:xml_base))
          .to eq(Lutaml::Xml::W3c::XmlBaseType)
      end

      it "registers :xml_id" do
        expect(Lutaml::Model::Type.lookup(:xml_id))
          .to eq(Lutaml::Xml::W3c::XmlIdType)
      end
    end

    describe "XSI types registered" do
      it "registers :xsi_type" do
        expect(Lutaml::Model::Type.lookup(:xsi_type))
          .to eq(Lutaml::Xml::W3c::XsiType)
      end

      it "registers :xsi_nil" do
        expect(Lutaml::Model::Type.lookup(:xsi_nil))
          .to eq(Lutaml::Xml::W3c::XsiNil)
      end

      it "registers :xsi_schema_location" do
        expect(Lutaml::Model::Type.lookup(:xsi_schema_location))
          .to eq(Lutaml::Xml::W3c::XsiSchemaLocationType)
      end

      it "registers :xsi_no_namespace_schema_location" do
        expect(Lutaml::Model::Type.lookup(:xsi_no_namespace_schema_location))
          .to eq(Lutaml::Xml::W3c::XsiNoNamespaceSchemaLocationType)
      end
    end

    describe "XLink types registered" do
      it "registers :xlink_href" do
        expect(Lutaml::Model::Type.lookup(:xlink_href))
          .to eq(Lutaml::Xml::W3c::XlinkHrefType)
      end

      it "registers :xlink_type" do
        expect(Lutaml::Model::Type.lookup(:xlink_type))
          .to eq(Lutaml::Xml::W3c::XlinkTypeAttrType)
      end

      it "registers :xlink_role" do
        expect(Lutaml::Model::Type.lookup(:xlink_role))
          .to eq(Lutaml::Xml::W3c::XlinkRoleType)
      end

      it "registers :xlink_arcrole" do
        expect(Lutaml::Model::Type.lookup(:xlink_arcrole))
          .to eq(Lutaml::Xml::W3c::XlinkArcroleType)
      end

      it "registers :xlink_title" do
        expect(Lutaml::Model::Type.lookup(:xlink_title))
          .to eq(Lutaml::Xml::W3c::XlinkTitleType)
      end

      it "registers :xlink_show" do
        expect(Lutaml::Model::Type.lookup(:xlink_show))
          .to eq(Lutaml::Xml::W3c::XlinkShowType)
      end

      it "registers :xlink_actuate" do
        expect(Lutaml::Model::Type.lookup(:xlink_actuate))
          .to eq(Lutaml::Xml::W3c::XlinkActuateType)
      end
    end
  end

  describe "Symbol-based attribute definition (without explicit registration)" do
    it "allows defining attribute with symbol type :xlink_href" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :href, :xlink_href
        end
      end.not_to raise_error
    end

    it "allows defining attribute with symbol type :xml_lang" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :lang, :xml_lang
        end
      end.not_to raise_error
    end

    it "allows defining attribute with symbol type :xsi_nil" do
      expect do
        Class.new(Lutaml::Model::Serializable) do
          attribute :nil_attr, :xsi_nil
        end
      end.not_to raise_error
    end
  end

  describe "W3C types loaded with require 'lutaml/model'" do
    # Regression test: ensure W3C types are registered when require "lutaml/model"
    # is called, without requiring any additional explicit requires.
    # This tests the fix for: https://github.com/riboseinc/lutaml-model/issues/XXX

    let(:lib_path) { File.expand_path("../../../../lib", __FILE__) }

    it "registers all W3C types in Type registry after require 'lutaml/model'" do
      # Use subprocess to ensure fresh require - write code to temp file to avoid shell escaping issues
      temp_script = Tempfile.new(["w3c_test", ".rb"])
      begin
        temp_script.write(<<~RUBY)
          require "lutaml/model"
          types = [:xml_lang, :xml_space, :xml_base, :xml_id,
                    :xsi_type, :xsi_nil, :xsi_schema_location, :xsi_no_namespace_schema_location,
                    :xlink_href, :xlink_type, :xlink_role, :xlink_arcrole,
                    :xlink_title, :xlink_show, :xlink_actuate]
          missing = types.reject { |t| Lutaml::Model::Type.instance_variable_get(:@registry)&.key?(t) }
          exit(missing.any? ? 1 : 0)
        RUBY
        temp_script.close

        # rubocop:disable Style/CommandLiteral
        result = `#{RbConfig.ruby} -I#{lib_path} #{temp_script.path} 2>&1`
        # rubocop:enable Style/CommandLiteral

        expect($?.success?).to eq(true),
          "W3C types not registered after require 'lutaml/model'. " \
          "Types should be automatically loaded. Output: #{result}"
      ensure
        temp_script.unlink
      end
    end

    it "allows Type.lookup for all W3C symbols after require 'lutaml/model'" do
      temp_script = Tempfile.new(["w3c_test", ".rb"])
      begin
        temp_script.write(<<~RUBY)
          require "lutaml/model"
          types = [:xml_lang, :xml_space, :xml_base, :xml_id,
                    :xsi_type, :xsi_nil, :xsi_schema_location, :xsi_no_namespace_schema_location,
                    :xlink_href, :xlink_type, :xlink_role, :xlink_arcrole,
                    :xlink_title, :xlink_show, :xlink_actuate]
          types.each do |t|
            Lutaml::Model::Type.lookup(t)
          end
          exit(0)
        RUBY
        temp_script.close

        # rubocop:disable Style/CommandLiteral
        result = `#{RbConfig.ruby} -I#{lib_path} #{temp_script.path} 2>&1`
        # rubocop:enable Style/CommandLiteral

        expect($?.success?).to eq(true),
          "Type.lookup failed for W3C symbols after require 'lutaml/model'. " \
          "Output: #{result}"
      ensure
        temp_script.unlink
      end
    end

    it "allows symbol-based attribute definition after require 'lutaml/model'" do
      temp_script = Tempfile.new(["w3c_test", ".rb"])
      begin
        temp_script.write(<<~RUBY)
          require "lutaml/model"
          Class.new(Lutaml::Model::Serializable) do
            attribute :href, :xlink_href
            attribute :lang, :xml_lang
            attribute :nil_attr, :xsi_nil
          end
          exit(0)
        RUBY
        temp_script.close

        # rubocop:disable Style/CommandLiteral
        result = `#{RbConfig.ruby} -I#{lib_path} #{temp_script.path} 2>&1`
        # rubocop:enable Style/CommandLiteral

        expect($?.success?).to eq(true),
          "Symbol-based attribute definition failed after require 'lutaml/model'. " \
          "Output: #{result}"
      ensure
        temp_script.unlink
      end
    end
  end
end
