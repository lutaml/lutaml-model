require "spec_helper"

RSpec.describe Lutaml::Model::Type::Duration do
  describe ".cast" do
    subject(:cast) { described_class.cast(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with valid duration strings" do
      context "with years, months, days" do
        let(:value) { "P1Y2M3D" }

        it { is_expected.to eq("P1Y2M3D") }
      end

      context "with hours, minutes, seconds" do
        let(:value) { "PT4H5M6S" }

        it { is_expected.to eq("PT4H5M6S") }
      end

      context "with combined date and time" do
        let(:value) { "P1Y2M3DT4H5M6S" }

        it { is_expected.to eq("P1Y2M3DT4H5M6S") }
      end

      context "with decimal seconds" do
        let(:value) { "PT0.5S" }

        it { is_expected.to eq("PT0.5S") }
      end

      context "with only year" do
        let(:value) { "P1Y" }

        it { is_expected.to eq("P1Y") }
      end

      context "with only time" do
        let(:value) { "PT1H" }

        it { is_expected.to eq("PT1H") }
      end
    end

    context "with Duration instance" do
      let(:duration_instance) { described_class.new("P1Y2M3D") }
      let(:value) { duration_instance }

      it { is_expected.to eq("P1Y2M3D") }
    end
  end

  describe ".serialize" do
    subject(:serialize) { described_class.serialize(value) }

    context "with nil value" do
      let(:value) { nil }

      it { is_expected.to be_nil }
    end

    context "with valid duration string" do
      let(:value) { "P1Y2M3DT4H5M6S" }

      it { is_expected.to eq("P1Y2M3DT4H5M6S") }
    end

    context "with Duration instance" do
      let(:duration_instance) { described_class.new("PT4H30M") }
      let(:value) { duration_instance }

      it { is_expected.to eq("PT4H30M") }
    end
  end

  describe ".xsd_type" do
    it "returns xs:duration" do
      expect(described_class.xsd_type).to eq("xs:duration")
    end
  end

  describe "#initialize" do
    context "with valid duration string" do
      subject(:duration) { described_class.new("P1Y2M3DT4H5M6.5S") }

      it "parses years correctly" do
        expect(duration.years).to eq(1)
      end

      it "parses months correctly" do
        expect(duration.months).to eq(2)
      end

      it "parses days correctly" do
        expect(duration.days).to eq(3)
      end

      it "parses hours correctly" do
        expect(duration.hours).to eq(4)
      end

      it "parses minutes correctly" do
        expect(duration.minutes).to eq(5)
      end

      it "parses seconds correctly" do
        expect(duration.seconds).to eq(6.5)
      end
    end

    context "with partial duration" do
      subject(:duration) { described_class.new("P1Y") }

      it "parses year correctly" do
        expect(duration.years).to eq(1)
      end

      it "sets other components to zero" do
        expect(duration.months).to eq(0)
        expect(duration.days).to eq(0)
        expect(duration.hours).to eq(0)
        expect(duration.minutes).to eq(0)
        expect(duration.seconds).to eq(0.0)
      end
    end

    context "with Duration instance" do
      subject(:duration) { described_class.new(original) }

      let(:original) { described_class.new("P1Y2M") }

      it "copies years" do
        expect(duration.years).to eq(1)
      end

      it "copies months" do
        expect(duration.months).to eq(2)
      end
    end
  end

  describe "#to_s" do
    let(:duration) { described_class.new("P1Y2M3DT4H5M6S") }

    it "returns the original duration string" do
      expect(duration.to_s).to eq("P1Y2M3DT4H5M6S")
    end
  end

  describe "integration with Serializable" do
    let(:model_class) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :processing_time, :duration

        xml do
          element "task"
          map_element "processingTime", to: :processing_time
        end
      end
    end

    it "serializes duration correctly" do
      instance = model_class.new(processing_time: "P1Y2M3D")
      xml = instance.to_xml
      expect(xml).to include("<processingTime>P1Y2M3D</processingTime>")
    end

    it "deserializes duration correctly" do
      xml = "<task><processingTime>PT4H30M</processingTime></task>"
      instance = model_class.from_xml(xml)
      expect(instance.processing_time).to eq("PT4H30M")
    end

    it "handles nil duration" do
      instance = model_class.new(processing_time: nil)
      expect(instance.processing_time).to be_nil
    end
  end
end
