# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # A named rejection from the exporter: the construct is
      # constructor-contract, not schema, and has no declarative
      # equivalent in the LML document (lutaml-model#1033 design
      # decision #3).
      class RejectedError < StandardError
        attr_reader :reason, :klass, :detail

        # +reason+ is one of:
        #   :lambda_default            — a default given as a Proc
        #   :custom_initialize         — the model overrides `initialize`
        #   :imperative_element_order  — ordered content with no
        #                                declarative sequence
        #   :unknown_type              — a type with no registry name
        #   :not_serializable          — the class does not include
        #                                Serializable
        def initialize(reason, klass, detail = nil)
          @reason = reason
          @klass = klass
          @detail = detail
          message = "cannot export #{klass} to LML: #{reason}"
          message += " (#{detail})" if detail
          super(message)
        end
      end
    end
  end
end
