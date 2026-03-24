# frozen_string_literal: true

require "spec_helper"

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
      Lutaml::Xml::W3c.register_types!
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
end
