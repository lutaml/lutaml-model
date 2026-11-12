# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"
require "lutaml/model/lml"

RSpec.describe "LML review round-3 misc fixes" do
  let(:lml) { Lutaml::Model::Lml }
  let(:fixtures) { File.expand_path("../../fixtures/lml_artifacts", __dir__) }

  describe "L3: Bundle owns private copies of its inputs" do
    it "does not change identity or freeze the caller's strings" do
      root = +"A@default"
      capability = +"json"
      name = +"A"
      doc = { "lml" => 2, "model" => name, "register" => "default", "attributes" => [] }
      bundle = lml::Bundle.new(roots: [root], models: { "A@default" => doc },
                               capabilities: [capability])
      before = bundle.checksum

      root << "x"
      capability << "y"
      name << "z"

      expect(bundle.roots).to eq(["A@default"])
      expect(bundle.capabilities).to eq(["json"])
      expect(bundle.checksum).to eq(before)
      expect(name.frozen?).to be(false)
      expect(root.frozen?).to be(false)
      expect(bundle.roots).to all(be_frozen)
      expect(bundle.models["A@default"]["model"]).to be_frozen
    end
  end

  describe "L9: OrderedContent.apply refuses tokens serialization overrides" do
    let(:klass) do
      Class.new(Lutaml::Model::Serializable) do
        attribute :text, :string, collection: true
        attribute :em, :string, collection: true
        xml do
          root "mixed"
          mixed_content
          map_content to: :text
          map_element "em", to: :em
        end

        def self.name = "ReviewMisc::Mixed"
      end
    end
    let(:descriptor) do
      lml::OrderedContent.descriptor_for(klass, mapping: klass.mappings_for(:xml))
    end
    let(:text0) { { "kind" => "text", "attribute" => "text", "index" => 0 } }
    let(:em0) { { "kind" => "element", "attribute" => "em", "index" => 0 } }
    let(:literal) { { "kind" => "text", "literal" => "ZZ" } }

    def apply(attrs, tokens)
      instance = klass.new(**attrs)
      lml::OrderedContent.apply(descriptor, tokens, instance)
      instance
    end

    it "rejects a literal that a remaining content value would override" do
      expect { apply({ text: ["a"], em: ["x"] }, [literal, em0]) }
        .to raise_error(lml::RejectedError) { |e| expect(e.message).to include("invalid_ordered_content") }
      expect { apply({ text: %w[a b], em: [] }, [text0, literal]) }
        .to raise_error(lml::RejectedError, /invalid_ordered_content/)
    end

    it "rejects a literal CDATA token the content values would replace" do
      expect { apply({ text: ["a"], em: [] }, [{ "kind" => "cdata", "literal" => "C" }]) }
        .to raise_error(lml::RejectedError, /invalid_ordered_content.*would be overridden/)
    end

    it "still accepts literals the serializer keeps" do
      cdata = { "kind" => "cdata", "literal" => "C" }
      expect(apply({ text: ["a"], em: [] }, [text0, cdata]).to_xml).to include("C")

      instance = apply({ text: ["a"], em: ["x"] }, [text0, literal, em0])
      expect(instance.to_xml).to include("ZZ")
      expect(apply({ text: [], em: ["x"] }, [literal, em0]).to_xml).to include("ZZ")
    end
  end

  describe "L10: ArtifactVerifier" do
    it "is autoloaded from Lutaml::Model::Lml" do
      out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e",
                                    'require "lutaml/model"; require "lutaml/model/lml"; ' \
                                    "puts Lutaml::Model::Lml::ArtifactVerifier.name")
      expect(status.success?).to be(true), out
      expect(out).to include("Lutaml::Model::Lml::ArtifactVerifier")
    end

    it "keeps digest and pathname out of top-level requires" do
      source = File.read(File.expand_path("../../../lib/lutaml/model/lml/artifact_verifier.rb", __dir__))
      expect(source).not_to match(/^require ["'](digest|pathname)["']/)
    end

    context "with a manifest lacking files" do
      let(:manifest) do
        JSON.parse(File.read(File.join(fixtures, "valid.json"))).tap { |m| m.delete("files") }
      end
      let(:pin) { lml::ArtifactVerifier.checksum(manifest) }

      it "raises the named error, not KeyError" do
        verifier = lml::ArtifactVerifier.new(root: fixtures, expected_sha256: pin)
        expect { verifier.verify(manifest) }
          .to raise_error(lml::ArtifactVerifier::Error, %r{invalid_document: /files})
      end

      it "makes the CLI exit 1 with a JSON verdict" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "manifest.json")
          File.write(path, JSON.generate(manifest))
          out, err, status = Open3.capture3(RbConfig.ruby, "scripts/lml/verify_artifacts.rb",
                                            "--manifest", path, "--expected-sha256", pin)
          expect(status.exitstatus).to eq(1), "#{out}#{err}"
          expect(JSON.parse(err)).to include("verified" => false)
        end
      end
    end
  end

  describe "L10: CI fixtures-unchanged step" do
    let(:step) do
      workflow = YAML.load_file(File.expand_path("../../../.github/workflows/lml-conformance.yml", __dir__))
      workflow["jobs"].values.flat_map { |job| job["steps"] }
        .find { |s| s["name"] == "Ensure verification leaves fixtures unchanged" }
    end

    it "fails on untracked files as well as modifications" do
      Dir.mktmpdir do |dir|
        env = { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@e", "GIT_COMMITTER_NAME" => "t",
                "GIT_COMMITTER_EMAIL" => "t@e" }
        FileUtils.mkdir_p(File.join(dir, "scripts/lml"))
        FileUtils.mkdir_p(File.join(dir, "spec/fixtures"))
        File.write(File.join(dir, "scripts/lml/a.rb"), "1")
        [%w[git init -q], %w[git add .], %w[git commit -qm x]].each do |cmd|
          system(env, *cmd, chdir: dir, exception: true)
        end
        run = -> { Open3.capture2e("sh", "-ec", step["run"], chdir: dir)[1].exitstatus }

        expect(run.call).to eq(0)
        File.write(File.join(dir, "spec/fixtures/stray.json"), "{}")
        expect(run.call).to eq(1)
      end
    end
  end
end
