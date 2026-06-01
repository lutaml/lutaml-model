# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        # XSD restriction collector. Inherits the shared facet flow from
        # Lutaml::Model::Schema::Restriction; adds the XSD-only TRANSFORM
        # facet (used by SUPPORTED_DATA_TYPES validations like
        # normalizedString's whitespace transform).
        class Restriction < Lutaml::Model::Schema::Restriction
          attr_accessor :transform

          # XSD-only: applies an arbitrary `value = <expr>` line before
          # `super`. RNG has no equivalent — RELAX NG's facet vocabulary
          # doesn't include arbitrary value transforms.
          TRANSFORM = ERB.new(<<~TMPL, trim_mode: "-")
            <%= "\#{indent}value = \#{transform}" %>
          TMPL

          FACET_STEPS = (
            Lutaml::Model::Schema::Restriction::FACET_STEPS +
            [[:transform_present?, TRANSFORM]]
          ).freeze

          def required_files
            if base_class_name == :decimal
              %(require "bigdecimal")
            elsif !SimpleType::SUPPORTED_DATA_TYPES.dig(base_class_name, :skippable)
              "require_relative \"#{Utils.snake_case(base_class_name)}\""
            end
          end

          def transform_present?
            Utils.present?(transform)
          end

          private

          def base_class_name
            return if Utils.blank?(base_class)

            base_class.split(":").last.to_sym
          end
        end
      end
    end
  end
end
