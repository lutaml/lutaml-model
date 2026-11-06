# frozen_string_literal: true

require "optparse"
require "fileutils"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require_relative "../../spec/support/lml_conformance"

options = { check: false, package: File.expand_path("../../spec/fixtures/lml_conformance/core", __dir__) }
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/lml/export_conformance.rb [--check] [--package DIRECTORY]"
  parser.on("--check", "Check pinned files without rewriting") { options[:check] = true }
  parser.on("--package DIRECTORY", "Explicit core package directory") { |path| options[:package] = path }
end.parse!

unless options[:check]
  FileUtils.mkdir_p(options[:package])
  LmlConformance.files.each do |path, bytes|
    File.binwrite(File.join(options[:package], path), bytes)
  end
end
report = LmlConformance.check(options[:package])
puts LmlConformance.json(report)
exit(report.fetch("errors").empty? ? 0 : 1)
