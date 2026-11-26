# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Lml
    module Types
      # LML `definition` body text. The grammar allows literal braces to
      # be escaped (\{ \}) so they do not close the definition block;
      # casting unescapes them and normalizes line indentation. One
      # implementation shared by every attribute declared with this
      # type — no per-model (de)serialization procs.
      class TextType < Lutaml::Model::Type::String
        def self.cast(value, options = {})
          text = super
          return nil if text.nil?
          return text if Lutaml::Model::Utils.uninitialized?(text)

          text.gsub(/\\}/, '}')
              .gsub(/\\{/, '{')
              .split("\n")
              .map(&:strip)
              .join("\n")
        end
      end
    end
  end
end
