# frozen_string_literal: true

require "yaml"

module Lutaml
  module KeyValue
    module Adapter
      module Yamls
        # The production YAMLS stream adapter: whole-stream Psych
        # load_stream first, then the per-document split fallback —
        # invalid documents warn and are skipped, valid ones stand.
        # Formerly the split-only parser; the load_stream primary was
        # lifted from Lutaml::Yamls::Adapter::StandardAdapter when the
        # implementations were unified under the key-value namespace.
        class StandardAdapter < Document
          FORMAT_SYMBOL = :yamls

          def self.parse(yamls, _options = {})
            results = []

            YAML.load_stream(yamls) do |doc|
              next if doc.nil?

              results << doc
            end

            results
          rescue *Lutaml::Model::Utils.yaml_parse_errors
            warn "Skipping invalid yaml: #{yamls.lines.first}"
            parse_with_split(yamls)
          end

          def self.parse_with_split(yamls)
            results = []

            yamls.split(/^---\s*$/).each do |yaml|
              next if yaml.strip.empty?

              begin
                results << YAML.safe_load(yaml, aliases: true)
              rescue *Lutaml::Model::Utils.yaml_parse_errors => e
                warn "Skipping invalid yaml: #{e.message}"
              end
            end

            results
          end
          private_class_method :parse_with_split

          def to_yamls(*_args)
            (@yamls || []).map do |yaml|
              YAML.dump(yaml).strip
            end.join("\n")
          end
        end
      end
    end
  end
end
