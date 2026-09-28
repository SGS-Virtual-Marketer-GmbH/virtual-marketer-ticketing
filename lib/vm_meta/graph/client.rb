# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Thin wrapper around the Meta Graph API (Messenger Send API / Instagram
# Messaging API share the same '/{page_id}/messages' endpoint and error
# shape). Uses Zammad's own UserAgent for plain GET/POST (JSON) calls, the
# same as most other outbound HTTP integrations in this app; only the
# attachment upload needs a hand-built multipart/form-data body, since
# UserAgent has no multipart support.
class VmMeta::Graph::Client

  attr_reader :access_token

  def initialize(access_token:)
    raise ArgumentError, __("The required parameter 'access_token' is missing.") if access_token.blank?

    @access_token = access_token
  end

  def get(path, params = {})
    result = UserAgent.get(build_url(path), params, request_options)

    handle_result(result)
  end

  def post(path, params = {})
    result = UserAgent.post(build_url(path), params, request_options.merge(json: true))

    handle_result(result)
  end

  # Multipart upload + send in one call, as the Send API expects for
  # Messenger attachments (message={"attachment":{...}} + filedata).
  # 'fields' values are sent as-is (already-JSON-encoded strings where
  # needed); this method itself does no JSON encoding.
  def post_multipart(path, fields:, file_content:, filename:, mime_type:)
    uri      = URI.parse(build_url(path))
    boundary = SecureRandom.hex(16)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = uri.scheme == 'https'
    http.open_timeout = 15
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri)
    request['Content-Type']  = "multipart/form-data; boundary=#{boundary}"
    request['Authorization'] = "Bearer #{access_token}"
    request.body = multipart_body(boundary:, fields:, file_content:, filename:, mime_type:)

    handle_net_http_response(http.request(request))
  end

  private

  # The page token goes in the Authorization header, never the query
  # string: a URL ends up in error messages and logs, a header does not.
  def build_url(path)
    "#{VmMeta::GRAPH_BASE_URL}/#{VmMeta::GRAPH_API_VERSION}/#{path}"
  end

  def request_options
    { open_timeout: 15, read_timeout: 30, json: true, bearer_token: access_token }
  end

  def multipart_body(boundary:, fields:, file_content:, filename:, mime_type:)
    body = +''
    body.force_encoding(Encoding::ASCII_8BIT)

    fields.each do |key, value|
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
      body << value.to_s.b
      body << "\r\n"
    end

    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"filedata\"; filename=\"#{filename}\"\r\n"
    body << "Content-Type: #{mime_type}\r\n\r\n"
    body << file_content.to_s.b
    body << "\r\n--#{boundary}--\r\n"

    body
  end

  def handle_result(result)
    return result.data || {} if result.success?

    body  = safe_parse(result.body)
    error = body['error'] if body.is_a?(Hash)

    raise VmMeta::Graph::Client::GraphAPIError.new(
      error&.dig('message') || result.error || __('Unknown Graph API error.'),
      code:        error&.dig('code'),
      http_status: result.code.to_i,
    )
  end

  def handle_net_http_response(response)
    code = response.code.to_i
    body = safe_parse(response.body)

    return body if code >= 200 && code < 300

    error = body['error'] if body.is_a?(Hash)

    raise VmMeta::Graph::Client::GraphAPIError.new(
      error&.dig('message') || "HTTP #{code}",
      code:        error&.dig('code'),
      http_status: code,
    )
  end

  def safe_parse(body)
    return {} if body.blank?

    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  class GraphAPIError < StandardError
    attr_reader :code, :http_status

    def initialize(message, code: nil, http_status: nil)
      @code        = code
      @http_status = http_status

      super(message)
    end

    # Same spirit as Whatsapp::Client::CloudAPIError#retryable? - 5xx and
    # rate limiting are worth a retry, a hard client-side rejection (bad
    # token, unsupported recipient, ...) is not.
    def retryable?
      return true if http_status.to_i >= 500
      return true if http_status.to_i == 429

      # Graph API's own transient/rate-limit error codes.
      [1, 2, 4, 17, 32, 613].include?(code)
    end
  end
end
