# frozen_string_literal: true

require 'json'
require 'parsanol'
# parsanol/parg does not require the parsanol core itself; both are
# needed before the compiler builds atoms.
require 'parsanol/parg'

module Lutaml
  module Lml
    # LML grammar: the PARG source (grammar/lml.parg) is the single
    # source of truth; grammar/lml.artifact.json is its compiled form
    # (regenerate with `rake parg`). Loading the committed artifact
    # costs ~4ms where compiling the text costs ~500ms, so the
    # artifact is the preferred path; its embedded source binds it to
    # the .parg, and a drifted or missing artifact falls back to
    # compiling (the sync spec keeps the pair honest in CI).
    module Grammar
      ENTRY = 'diagram'
      GRAMMAR_PATH = File.expand_path('grammar/lml.parg', __dir__)
      ARTIFACT_PATH = File.expand_path('grammar/lml.artifact.json', __dir__)

      # The language version this build implements, read from the
      # compiled artifact (falling back to the grammar text when the
      # artifact is absent). Version negotiation compares document
      # prologues against it.
      def self.version
        @version ||= begin
          envelope = JSON.parse(File.read(ARTIFACT_PATH, encoding: 'UTF-8'))
          envelope['version'].to_s
        rescue StandardError
          File.read(GRAMMAR_PATH, encoding: 'UTF-8')[/grammar \w+ version "([^"]+)"/, 1] || '0.0.0'
        end
      end

      def self.artifact
        @artifact ||= load_artifact || compile_artifact
      end

      # The grammar text and artifact carry UTF-8 (em-dashes in
      # comments); pin the encoding so non-UTF-8 locales (LANG=C CI
      # images) cannot raise InvalidByteSequenceError on read.
      def self.load_artifact
        return unless File.exist?(ARTIFACT_PATH)

        envelope = JSON.parse(File.read(ARTIFACT_PATH, encoding: 'UTF-8'))
        return unless envelope['source'] == File.read(GRAMMAR_PATH, encoding: 'UTF-8')

        Parsanol::PARG::Artifact.new(envelope, ARTIFACT_PATH, File.dirname(ARTIFACT_PATH))
      end

      def self.compile_artifact
        document = Parsanol::PARG::Parser.new(File.read(GRAMMAR_PATH, encoding: 'UTF-8')).parse
        Parsanol::PARG::Artifact.new(
          Parsanol::PARG::Compiler.compile(document).envelope, nil, nil
        )
      end
    end
  end
end
