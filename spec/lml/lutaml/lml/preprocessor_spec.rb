# frozen_string_literal: true

require "spec_helper"
require_relative "../../lml_spec_setup"
require "tempfile"
require "fileutils"

RSpec.describe Lutaml::Lml::Preprocessor do
  def make_file(content, name = "test.lutaml")
    file = Tempfile.new([name.gsub(/\..*/, ""), File.extname(name)])
    file.write(content)
    file.rewind
    file
  end

  describe ".call" do
    it "returns file content unchanged for simple files" do
      file = make_file("diagram TestDiagram\nend")
      result = described_class.call(file)
      expect(result).to eq("diagram TestDiagram\nend")
      file.close!
    end

    it "preserves // comments for grammar-level trivia" do
      file = make_file("diagram Test // this is a comment\nend")
      result = described_class.call(file)
      expect(result).to eq("diagram Test // this is a comment\nend")
      file.close!
    end

    it "preserves inline comments and raises on unterminated block comments" do
      file = make_file("class MyClass // inline comment\ntitle \"Test\" // another\nend")
      result = described_class.call(file)
      expect(result).to include("// inline comment")
      file.close!

      bad = make_file("class MyClass {\n/* never closed\n")
      expect { described_class.call(bad) }
        .to raise_error(Lutaml::Lml::Error, /unterminated block comment/)
      bad.close!
    end
  end

  describe "include directives" do
    it "includes referenced files" do
      shared_content = "class SharedClass\nend"
      shared_file = make_file(shared_content, "shared.lutaml")

      main_content = "diagram Test\ninclude #{File.basename(shared_file.path)}\nend"
      main_file = Tempfile.new(["main", ".lutaml"])
      main_file.write(main_content)
      main_file.rewind

      result = described_class.call(main_file)
      expect(result).to include("SharedClass")
      expect(result).not_to include("include")
      main_file.close!
      shared_file.close!
    end

    it "raises on missing include files" do
      file = make_file("diagram Test\ninclude nonexistent.lutaml\nend")
      expect { described_class.call(file) }
        .to raise_error(Lutaml::Lml::Error, /cannot read include/)
      file.close!
    end

    it "expands includes nested inside included files" do
      dir = Dir.mktmpdir
      inner = File.join(dir, "inner.lutaml")
      middle = File.join(dir, "middle.lutaml")
      File.write(inner, "class Inner\nend")
      File.write(middle, "class Middle\ninclude inner.lutaml\nend")

      main = Tempfile.new(%w[main .lutaml])
      main.write("diagram Test\ninclude #{middle}\nend")
      main.rewind

      result = described_class.call(main)
      expect(result).to include("Middle")
      expect(result).to include("Inner")
      expect(result).not_to include("include")
      main.close!
      FileUtils.rm_rf(dir)
    end

    it "resolves nested includes relative to the including file" do
      dir = Dir.mktmpdir
      subdir = File.join(dir, "sub")
      FileUtils.mkdir(subdir)
      File.write(File.join(subdir, "inner.lutaml"), "class Inner\nend")
      File.write(File.join(dir, "middle.lutaml"), "class Middle\ninclude sub/inner.lutaml\nend")

      main = Tempfile.new(%w[main .lutaml])
      main.write("diagram Test\ninclude #{File.join(dir, 'middle.lutaml')}\nend")
      main.rewind

      result = described_class.call(main)
      expect(result).to include("Inner")
      main.close!
      FileUtils.rm_rf(dir)
    end

    it "raises on circular includes" do
      dir = Dir.mktmpdir
      a = File.join(dir, "a.lutaml")
      b = File.join(dir, "b.lutaml")
      File.write(a, "class A\ninclude #{b}\nend")
      File.write(b, "class B\ninclude #{a}\nend")

      main = Tempfile.new(%w[main .lutaml])
      main.write("diagram Test\ninclude #{a}\nend")
      main.rewind

      expect { described_class.call(main) }
        .to raise_error(Lutaml::Lml::Error, /circular include/)
      main.close!
      FileUtils.rm_rf(dir)
    end

    it "allows the same file included twice (non-circular)" do
      dir = Dir.mktmpdir
      shared = File.join(dir, "shared.lutaml")
      File.write(shared, "class Shared\nend")

      main = Tempfile.new(%w[main .lutaml])
      main.write("diagram Test\ninclude #{shared}\ninclude #{shared}\nend")
      main.rewind

      result = described_class.call(main)
      expect(result.scan("Shared").length).to eq(2)
      main.close!
      FileUtils.rm_rf(dir)
    end

    it "strips carriage returns from CRLF files" do
      file = make_file("diagram Test\r\ntitle \"x\"\r\n")
      result = described_class.call(file)
      expect(result).not_to include("\r")
      file.close!
    end

    it "raises on unreadable include files" do
      skip "Unix file modes not enforced on Windows" if Gem.win_platform?
      dir = Dir.mktmpdir
      unreadable = File.join(dir, "unreadable.lutaml")
      File.write(unreadable, "class Unreadable\nend")
      FileUtils.chmod(0o000, unreadable)
      main = Tempfile.new(%w[main .lutaml])
      main.write("diagram Test\ninclude #{unreadable}\nend")
      main.rewind

      expect { described_class.call(main) }
        .to raise_error(Lutaml::Lml::Error, /cannot read include/)
    ensure
      begin
        FileUtils.chmod(0o644, unreadable)
      rescue StandardError
        nil
      end
      main&.close!
      FileUtils.rm_rf(dir)
    end
  end

  describe "idempotency" do
    it "produces the same output when called twice on the same StringIO" do
      io = StringIO.new("diagram Test // comment\nend")
      first = described_class.call(io)
      second = described_class.call(io)
      expect(second).to eq(first)
    end
  end
end
