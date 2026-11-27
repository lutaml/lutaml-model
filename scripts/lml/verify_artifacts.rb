# frozen_string_literal: true

require "optparse"
require_relative "../../lib/lutaml/model/lml/artifact_verifier"

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |cli|
    cli.banner = "Usage: verify_artifacts.rb --manifest FILE --expected-sha256 DIGEST"
    cli.on("--manifest FILE") { |value| options[:manifest] = value }
    cli.on("--expected-sha256 DIGEST") { |value| options[:expected_sha256] = value }
    cli.on("--root DIRECTORY") { |value| options[:root] = value }
  end
  begin
    parser.parse!
    raise OptionParser::MissingArgument, "--manifest" unless options[:manifest]
    raise OptionParser::MissingArgument, "--expected-sha256" unless options[:expected_sha256]

    manifest = JSON.parse(File.read(options[:manifest], encoding: "UTF-8"))
    root = options[:root] || File.dirname(File.expand_path(options[:manifest]))
    verifier = Lutaml::Model::Lml::ArtifactVerifier.new(root: root,
                                                        expected_sha256: options[:expected_sha256])
    verifier.verify(manifest)
    puts JSON.generate("verified" => true, "target" => manifest["target"],
                       "files" => manifest["files"].length)
  rescue OptionParser::ParseError, JSON::ParserError, SystemCallError,
         Lutaml::Model::Lml::ArtifactVerifier::Error => e
    warn JSON.generate("verified" => false, "error" => e.message.scrub)
    exit 1
  end
end
