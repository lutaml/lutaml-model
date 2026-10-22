module Lutaml
  module Model
    # Raised when version detection reports a model version that no class
    # in the detected model's family declares (#265).
    class UnsupportedVersionError < Error
      def initialize(model_class, version)
        super(
          "no model in the #{model_class} family declares version " \
          "#{version.inspect}",
        )
      end
    end
  end
end
