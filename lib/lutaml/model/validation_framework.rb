# frozen_string_literal: true

require_relative "validation/issue"
require_relative "validation/layer_result"
require_relative "validation/report"
require_relative "validation/context"
require_relative "validation/rule"
require_relative "validation/registry"
require_relative "validation/profile"
require_relative "validation/remediation"
require_relative "validation/remediation_result"

module Lutaml
  module Model
    # Document-level validation framework. Orthogonal to the existing
    # attribute-level Validation module — this validates structural
    # integrity, cross-references, and conformance against domain rules.
    #
    # @example Run all registered rules
    #   issues = Lutaml::Model::Validation.validate(context, registry)
    # @example Run and raise on errors
    #   Lutaml::Model::Validation.validate!(context, registry)
    module Validation
      class << self
        def new_registry
          Registry.new
        end

        def validate(context, registry, profile: nil)
          rules = if profile
                    profile.resolve(registry)
                  else
                    registry.all
                  end

          all_issues = []
          rules.each do |rule|
            next unless rule.applicable?(context)

            issues = rule.check(context)
            if context.is_a?(Validation::Context)
              issues.each { |i| context.add_error(i) }
            end
            all_issues.concat(issues)
          end

          all_issues
        end

        def validate!(context, registry, profile: nil)
          issues = validate(context, registry, profile: profile)
          return if issues.empty?

          errors = issues.select(&:error?)
          unless errors.empty?
            raise ValidationError.new(format_errors(errors), issues: errors)
          end
        end

        private

        def format_errors(errors)
          errors.map { |e| "[#{e.code}] #{e.message}" }.join("\n")
        end
      end

      class ValidationError < StandardError
        attr_reader :issues

        def initialize(message, issues: [])
          super(message)
          @issues = issues
        end
      end
    end
  end
end
