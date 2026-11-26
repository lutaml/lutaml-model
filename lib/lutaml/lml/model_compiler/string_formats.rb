# frozen_string_literal: true

module Lutaml
  module Lml
    class ModelCompiler
      # Registers declared string_format handlers on
      # compiled classes.
      module StringFormats
        private

        # L5: register grammar-backed string formats. Class-level
        # declarations win; a models-block default applies to classes
        # without their own. Artifact resolution: the compiler's
        # artifacts map (name => path), else the string as a path.
        def register_string_formats(doc)
          defaults = doc.packages.flat_map(&:default_string_formats)
          doc.classes.each do |class_def|
            declared = Array(class_def.string_formats)
            declared.each { |fmt| register_string_format(class_def.name.to_s, fmt) }

            declared_formats = declared.map(&:format)
            defaults.reject { |fmt| declared_formats.include?(fmt.format) }
                    .each { |fmt| register_string_format(class_def.name.to_s, fmt) }
          end
        end

        def register_string_format(class_name, fmt)
          artifact_path = artifact_path_for(fmt.artifact.to_s)
          return unless artifact_path

          compiled = @compiled[class_name]
          return unless compiled

          Parsanol::PARG::Lutaml.register(compiled,
                                          format_name: fmt.format.to_sym,
                                          artifact: artifact_path,
                                          entry: fmt.root.to_s)
        end
      end
    end
  end
end
