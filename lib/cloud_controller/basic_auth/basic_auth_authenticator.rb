module CloudController
  module BasicAuth
    class BasicAuthAuthenticator
      def self.valid?(rack_env, credentials)
        auth = Rack::Auth::Basic::Request.new(rack_env)
        auth.provided? && auth.basic? && \
          auth.credentials == credentials.map { |encoded_cred| CGI.unescape(encoded_cred) }
      end
    end
  end
end
