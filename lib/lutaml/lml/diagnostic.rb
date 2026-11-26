# frozen_string_literal: true

require "lutaml/model"

module Lutaml
  module Lml
    # One diagnostic record: a code, severity, source location, message,
    # and a remedy. Codes are namespaced by stage (parse/validation/
    # hydration/contract) and listed in CODES, the single source of
    # truth also documented in the README.
    class Diagnostic < Lutaml::Model::Serializable
      CODES = {
        'parse/LML-001' => {
          severity: 'error',
          remedy: 'Fix the syntax at the reported position.',
        },
        'parse/LML-002' => {
          severity: 'error',
          remedy: 'Terminate the block comment with */.',
        },
        'parse/LML-003' => {
          severity: 'error',
          remedy: 'Check the include path and the included file.',
        },
        'validation/LML-V01' => {
          severity: 'error',
          remedy: 'Rename or remove the duplicate definition.',
        },
        'validation/LML-V02' => {
          severity: 'error',
          remedy: 'Rename or remove the duplicate attribute.',
        },
        'validation/LML-V03' => {
          severity: 'error',
          remedy: 'Populate the mandatory attribute on the instance.',
        },
        'validation/LML-V04' => {
          severity: 'error',
          remedy: 'Use a value matching the declared primitive type.',
        },
        'validation/LML-V05' => {
          severity: 'error',
          remedy: 'Use one of the values declared for the attribute.',
        },
        'validation/LML-V06' => {
          severity: 'error',
          remedy: 'Declare the attribute or remove it from the instance.',
        },
        'validation/LML-V07' => {
          severity: 'error',
          remedy: 'Point the reference at an existing instance or attribute.',
        },
        'validation/LML-V08' => {
          severity: 'error',
          remedy: 'Break the reference cycle.',
        },
        'validation/LML-V09' => {
          severity: 'error',
          remedy: 'Use a value matching the attribute pattern.',
        },
        'validation/LML-V10' => {
          severity: 'error',
          remedy: 'Fix the attribute pattern so that it compiles.',
        },
        'hydration/LML-H01' => {
          severity: 'error',
          remedy: 'Check the instance data against the compiled model.',
        },
        'contract/LML-C01' => {
          severity: 'error',
          remedy: 'Check the path of the input file.',
        },
        'contract/LML-C02' => {
          severity: 'error',
          remedy: 'Use one of the supported input formats.',
        },
        'contract/LML-C03' => {
          severity: 'error',
          remedy: 'Check the input file and its format.',
        },
        'contract/LML-C04' => {
          severity: 'error',
          remedy: 'Use a cardinality token such as 1, 0..1, or 0..n.',
        },
        'contract/LML-C05' => {
          severity: 'error',
          remedy: 'Check the imported view path and the imported files.',
        },
        'contract/LML-C06' => {
          severity: 'warning',
          remedy: 'Use a supported language version or upgrade lutaml-lml.',
        },
      }.freeze

      attribute :code, :string
      attribute :severity, :string, default: 'error'
      attribute :file, :string
      attribute :line, :integer
      attribute :column, :integer
      attribute :length, :integer
      attribute :message, :string
      attribute :remedy, :string

      key_value do
        map 'code', to: :code
        map 'severity', to: :severity
        map 'file', to: :file
        map 'line', to: :line
        map 'column', to: :column
        map 'length', to: :length
        map 'message', to: :message
        map 'remedy', to: :remedy
      end

      def self.build(code, message:, file: nil, line: nil, column: nil,
                     length: nil, severity: nil, remedy: nil)
        entry = CODES.fetch(code)
        new(
          code: code,
          severity: severity || entry[:severity],
          file: file,
          line: line,
          column: column,
          length: length,
          message: message,
          remedy: remedy || entry[:remedy],
        )
      end

      # Human rendering: `path:line:col: [CODE] message`, then the
      # remedy. Position segments are omitted when the parser could not
      # attach them.
      def to_s
        "#{location}[#{code}] #{message}#{remedy_suffix}"
      end

      def location
        parts = [file, line, column].compact
        parts.empty? ? '' : "#{parts.join(':')}: "
      end

      private

      def remedy_suffix
        remedy.to_s.empty? ? '' : "\n  remedy: #{remedy}"
      end
    end
  end
end
