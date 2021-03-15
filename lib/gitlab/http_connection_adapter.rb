# frozen_string_literal: true

# This class is part of the Gitlab::HTTP wrapper. Depending on the value
# of the global setting allow_local_requests_from_web_hooks_and_services this adapter
# will allow/block connection to internal IPs and/or urls.
#
# This functionality can be overridden by providing the setting the option
# allow_local_requests = true in the request. For example:
# Gitlab::HTTP.get('http://www.gitlab.com', allow_local_requests: true)
#
# This option will take precedence over the global setting.
module Gitlab
  class HTTPConnectionAdapter < HTTParty::ConnectionAdapter
    extend ::Gitlab::Utils::Override

    override :connection
    def connection
      @uri, hostname = validate_url!(uri)

      if options.key?(:http_proxyaddr)
        proxy_uri_with_port = uri_with_port(options[:http_proxyaddr], options[:http_proxyport])
        proxy_uri_validated = validate_url!(proxy_uri_with_port).first

        @options[:http_proxyaddr] = "#{proxy_uri_validated.host}#{proxy_uri_validated.path}"
        @options[:http_proxyport] = proxy_uri_validated.port
      end

      super.tap do |http|
        http.hostname_override = hostname if hostname
      end
    end

    private

    def validate_url!(url)
      Gitlab::UrlBlocker.validate!(url, allow_local_network: allow_local_requests?,
                                        allow_localhost: allow_local_requests?,
                                        dns_rebind_protection: dns_rebind_protection?)
    rescue Gitlab::UrlBlocker::BlockedUrlError => e
      raise Gitlab::HTTP::BlockedUrlError, "URL '#{url}' is blocked: #{e.message}"
    end

    def allow_local_requests?
      options.fetch(:allow_local_requests, allow_settings_local_requests?)
    end

    def dns_rebind_protection?
      return false if Gitlab.http_proxy_env?

      Gitlab::CurrentSettings.dns_rebinding_protection_enabled?
    end

    def allow_settings_local_requests?
      Gitlab::CurrentSettings.allow_local_requests_from_web_hooks_and_services?
    end

    def uri_with_port(address, port)
      uri = Addressable::URI.parse(address)
      uri.port = port if port.present?
      uri
    end
  end
end
