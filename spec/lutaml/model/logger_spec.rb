require "spec_helper"

RSpec.describe Lutaml::Model::Logger do
  describe ".warn" do
    it "formats message with path when provided" do
      message = "Test warning message"
      path = "example.rb:123"

      warning_output = capture_warning do
        described_class.warn(message, path)
      end

      expect(warning_output).to include("[Lutaml::Model] WARN:example.rb:123 Test warning message")
    end

    it "formats message without path when not provided" do
      message = "Test warning message"

      warning_output = capture_warning do
        described_class.warn(message)
      end

      expect(warning_output).to include("[Lutaml::Model] WARN: Test warning message")
    end
  end

  describe ".warn_future_deprecation" do
    it "shows deprecation warning with caller location" do
      old_method = "old_method"
      replacement = "new_method"

      warning_output = capture_warning do
        described_class.warn_future_deprecation(old: old_method,
                                                replacement: replacement)
      end

      expect(warning_output).to include("Usage of `old_method` is deprecated")
      expect(warning_output).to include("Please use `new_method` instead")
      expect(warning_output).to match(/:\d+:/) # Should include line number
    end
  end

  describe "integration with existing methods" do
    it "works with warn_auto_handling" do
      expect do
        described_class.warn_auto_handling(
          name: "test_attribute",
          caller_file: "test.rb",
          caller_line: 42,
        )
      end.not_to raise_error
    end
  end

  private

  def capture_warning
    # Capture stderr output
    original_stderr = $stderr
    $stderr = StringIO.new

    yield

    $stderr.string
  ensure
    $stderr = original_stderr
  end
end
