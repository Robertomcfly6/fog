require(File.expand_path(File.join(File.dirname(__FILE__), 'core')))

module Fog
  module HP
    extend Fog::Provider

    service(:cdn,     'hp/cdn',     'CDN')
    service(:compute, 'hp/compute', 'Compute')
    service(:storage, 'hp/storage', 'Storage')

    # legacy swauth 1.0/1.1 style authentication
    def self.authenticate_v1(options, connection_options = {})
      hp_auth_uri = options[:hp_auth_uri] || "https://region-a.geo-1.objects.hpcloudsvc.com/auth/v1.0/"
      endpoint = URI.parse(hp_auth_uri)
      @scheme = endpoint.scheme || "http"
      @host = endpoint.host || "region-a.geo-1.objects.hpcloudsvc.com"
      @port = endpoint.port.to_s || "80"
      if (endpoint.path)
        @auth_path = endpoint.path.slice(1, endpoint.path.length)  # remove the leading slash
      else
        @auth_path = "auth/v1.0"
      end
      service_url = "#{@scheme}://#{@host}:#{@port}"
      connection = Fog::Connection.new(service_url, false, connection_options)
      @hp_account_id = options[:hp_account_id]
      @hp_secret_key  = options[:hp_secret_key]
      response = connection.request({
        :expects  => [200, 204],
        :headers  => {
          'X-Auth-Key'  => @hp_secret_key,
          'X-Auth-User' => @hp_account_id
        },
        :host     => @host,
        :port     => @port,
        :method   => 'GET',
        :path     => @auth_path
      })
      response.headers.reject do |key, value|
        !['X-Server-Management-Url', 'X-Storage-Url', 'X-CDN-Management-Url', 'X-Auth-Token'].include?(key)
      end

      return {
        :auth_token => response.headers['X-Auth-Token'],
        :endpoint_url => response.headers['X-Server-Management-Url'],
        :cdn_storage_url => response.headers['X-Storage-Url']
      }
    end

    # keystone based control services style authentication
    def self.authenticate_v2(options, connection_options = {})
      hp_auth_uri = options[:hp_auth_uri] || "https://region-a.geo-1.identity.hpcloudsvc.com/v2.0/"
      endpoint = URI.parse(hp_auth_uri)
      @scheme = endpoint.scheme || "http"
      @host = endpoint.host || "region-a.geo-1.identity.hpcloudsvc.com"
      @port = endpoint.port.to_s || "80"
      if (endpoint.path)
        @auth_path = endpoint.path.slice(1, endpoint.path.length)  # remove the leading slash
      else
        @auth_path = "v2.0/"
      end
      service_url = "#{@scheme}://#{@host}:#{@port}"
      connection = Fog::Connection.new(service_url, false, connection_options)

      ### Implement HP Control Services Authentication services ###
      # Get the style of auth credentials passed, defaults to access/secret key style
      @hp_use_upass_auth_style = options[:hp_use_upass_auth_style] || false
      @hp_account_id = options[:hp_account_id]
      @hp_secret_key = options[:hp_secret_key]
      @hp_tenant_id  = options[:hp_tenant_id]
      @hp_service_type  = options[:hp_service_type] || "object-store"

      ### Decide which auth style to use
      unless (@hp_use_upass_auth_style)
        # If Access Key style credentials are provided, use that
        request_body = {
            'auth' => {
                'apiAccessKeyCredentials' => {
                    'accessKey' => "#{@hp_account_id}",
                    'secretKey' => "#{@hp_secret_key}"
                }
            }
        }
      else
        # Otherwise use the Username/Password style
        request_body = {
            'auth' => {
                'passwordCredentials' => {
                    'username' => "#{@hp_account_id}",
                    'password' => "#{@hp_secret_key}"
                }
            }
        }
      end
      # add tenant_id if specified
      request_body['auth']['tenantId'] = "#{@hp_tenant_id}" if @hp_tenant_id

      ### Make the call to CS to get auth token and service catalog
      response = connection.request(
        {
          :expects => 200,
          :headers => {
              'Content-Type' => 'application/json'
          },
          :host => @host,
          :port => @port,
          :method => 'POST',
          :body => MultiJson.encode(request_body),
          :path => @auth_path
        }
      )

      body = MultiJson.decode(response.body)
      ### fish out auth_token and endpoint for the service
      if body['access']['serviceCatalog']
        service_item = body['access']['serviceCatalog'].select {|s| s["type"] == @hp_service_type}.first
        if service_item and service_item['endpoints'] and service_item['endpoints'][0]
          endpoint_url = service_item['endpoints'][0]['publicURL']
          auth_token = body['access']['token']['id']
          return {
            :auth_token => auth_token,
            :endpoint_url => endpoint_url
          }
        else
          raise "No endpoints found for the service type: #{@hp_service_type}"
        end
      else
        raise "Unable to parse service catalog."
      end

    end

    class Mock
      def self.etag
        Fog::Mock.random_hex(32)
      end

      def self.key_fingerprint
        fingerprint = []
        20.times do
          fingerprint << Fog::Mock.random_hex(2)
        end
        fingerprint.join(':')
      end

      def self.key_material
        private_key = OpenSSL::PKey::RSA.generate(1024)
        public_key = private_key.public_key
        return private_key.to_s, public_key.to_s
      end

      def self.user_id
        "dev_" + Fog::Mock.random_numbers(14)
      end

      def self.instance_id
        Fog::Mock.random_numbers(6)
      end

      def self.ip_address
        ip = []
        4.times do
          ip << Fog::Mock.random_numbers(rand(3) + 1).to_i.to_s # remove leading 0
        end
        ip.join('.')
      end

    end

  end
end
