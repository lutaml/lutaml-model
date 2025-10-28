module Lutaml
  module Model
    class FormatAdapterNotSpecifiedError < Error
      def initialize(format)
        @format = format

        super(<<~MSG
          #{@format} Format Adapter Not Configured.

          It looks like no #{@format} format adapter has been specified.

          To resolve this, please configure adapter like this in your setup:

            Lutaml::Model::Config.#{@format}_adapter_type = :type

          NOTE: For using XML and TOML adapters, install the respective gems.

          For more details, check the configuration guide:
          https://github.com/lutaml/lutaml-model#configuration-1
        MSG
        )
      end
    end
  end
end
