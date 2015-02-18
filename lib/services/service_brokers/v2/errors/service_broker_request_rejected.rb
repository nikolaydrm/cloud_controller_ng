module VCAP::Services
  module ServiceBrokers
    module V2
      module Errors
        class ServiceBrokerRequestRejected < HttpResponseError
          def initialize(uri, method, response)
            begin
              hash = MultiJson.load(response.body)
            rescue MultiJson::ParseError
            end

            if hash.is_a?(Hash) && hash.key?('description')
              message = "Service broker error: #{hash['description']}"
            else
              message = "The service broker returned an error for the request to #{uri}: #{response.code} #{response.message}"
            end

            super(message, uri, method, response)
          end

          def response_code
            502
          end
        end
      end
    end
  end
end
