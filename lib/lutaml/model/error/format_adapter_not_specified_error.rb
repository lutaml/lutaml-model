module Lutaml
  module Model
    class FormatAdapterNotSpecifiedError < Error
      def initialize(format)
        @format = format

        super(<<~MSG
          #{@format} Format Adapter Not Configured.

          It looks like no #{@format} format adapter has been specified.

          To resolve this, please configure one of the following in your setup:

            # Option 1: Set a custom adapter class
            Lutaml::Model::Config.#{@format}_adapter = AdapterClass

            # Option 2: Set a predefined adapter type
            Lutaml::Model::Config.#{@format}_adapter_type = :type

          For more details, check the configuration guide:
          https://github.com/lutaml/lutaml-model#configuration-1
        MSG
        )
      end
    end
  end
end
