require "spec_helper"
require "lutaml/model/schema"

RSpec.describe Lutaml::Model::Schema::LmlCompiler do
  describe ".to_models" do
    context "with valid lml model definition files, it generates the models" do
      before do
        described_class.to_models(file, output_dir: dir, create_files: true)
        Dir.glob("#{dir}/**/*.rb").each { |file| require_relative file }
      end

      after do
        FileUtils.rm_rf(dir)
      end

      let(:dir) { Dir.mktmpdir }

      let(:file) { File.open("spec/fixtures/lml/test_model.lml") }

      it "validates if the files exist in the directory" do
        expect(File).to exist("#{dir}/iho_s102_check/validation_checks.rb")
        expect(File).to exist("#{dir}/iho_s102_check/validation_checks.rb")
      end

      it "validates if the IhoS102Check::ValidationChecks class is a collection" do
        expect(IhoS102Check::ValidationChecks <= Lutaml::Model::Collection).to eq(true)
      end

      it "validates if the IhoS102Check::ValidationCheck class is a serializable model" do
        expect(IhoS102Check::ValidationCheck <= Lutaml::Model::Serializable).to eq(true)
      end
    end

    context "when classes are generated from text and loaded but files are not created" do
      before do
        described_class.to_models(
          File.read("spec/fixtures/lml/test_model.lml"),
          load_classes: true,
        )
      end

      let(:expected_classes) do
        %w[
          IhoS102Check::ValidationChecks
          IhoS102Check::ValidationCheck
        ]
      end

      it "validates if the IhoS102Check::ValidationChecks class loaded" do
        expect(IhoS102Check::ValidationChecks).to be_a(Class)
      end

      it "validates if the IhoS102Check::ValidationCheck class is loaded" do
        expect(IhoS102Check::ValidationCheck).to be_a(Class)
      end
    end
  end
end
