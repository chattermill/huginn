module Agents
  class ChattermillResponseAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    MIME_RE = /\A\w+\/.+\z/
    HTTP_METHOD = "post"
    PROTOCOLS = %w(http https)
    API_ENDPOINT = "/webhooks/responses"
    DOMAINS = [
      { text: "Production", id: "app.chattermill.xyz" },
      { text: "Staging", id: "staging.chattermill.xyz" },
      { text: "Local (lvh.me)", id: "lvh.me:3000" },
      { text: "localhost", id: "localhost:3000" }
    ]
    BASIC_OPTIONS = %w(comment score kind stream created_at user_meta segments)

    can_dry_run!
    no_bulk_receive!
    default_schedule "never"

    description do
      <<-MD
        A Chattermill Response Agent receives events from other agents (or runs periodically), merges those events with the [Liquid-interpolated](https://github.com/cantino/huginn/wiki/Formatting-Events-using-Liquid) contents of `payload`, and sends the results as POST (or GET) requests to a specified url.  To skip merging in the incoming event, but still send the interpolated payload, set `no_merge` to `true`.

        The `post_url` field must specify where you would like to send requests. Please include the URI scheme (`http` or `https`).

        The `method` used can be any of `get`, `post`, `put`, `patch`, and `delete`.

        By default, non-GETs will be sent with form encoding (`application/x-www-form-urlencoded`).

        Change `content_type` to `json` to send JSON instead.

        Change `content_type` to `xml` to send XML, where the name of the root element may be specified using `xml_root`, defaulting to `post`.

        When `content_type` contains a [MIME](https://en.wikipedia.org/wiki/Media_type) type, and `payload` is a string, its interpolated value will be sent as a string in the HTTP request's body and the request's `Content-Type` HTTP header will be set to `content_type`. When `payload` is a string `no_merge` has to be set to `true`.

        If `emit_events` is set to `true`, the server response will be emitted as an Event and can be fed to a WebsiteAgent for parsing (using its `data_from_event` and `type` options). No data processing
        will be attempted by this Agent, so the Event's "body" value will always be raw text.
        The Event will also have a "headers" hash and a "status" integer value.
        Set `event_headers_style` to one of the following values to normalize the keys of "headers" for downstream agents' convenience:

          * `capitalized` (default) - Header names are capitalized; e.g. "Content-Type"
          * `downcased` - Header names are downcased; e.g. "content-type"
          * `snakecased` - Header names are snakecased; e.g. "content_type"
          * `raw` - Backward compatibility option to leave them unmodified from what the underlying HTTP library returns.

        Other Options:

          * `headers` - When present, it should be a hash of headers to send with the request.
          * `basic_auth` - Specify HTTP basic auth parameters: `"username:password"`, or `["username", "password"]`.
          * `disable_ssl_verification` - Set to `true` to disable ssl verification.
          * `user_agent` - A custom User-Agent name (default: "Faraday v#{Faraday::VERSION}").
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "status": 200,
          "headers": {
            "Content-Type": "text/html",
            ...
          },
          "body": "<html>Some data...</html>"
        }
    MD

    def default_options
      {
        'protocol' => 'https',
        'domain' => 'app.chattermill.xyz',
        'comment' => '{{ data.comment }}',
        'score' => '{{ data.score }}',
        'kind' => 'review',
        'created_at' => '{{ data.date }}',
        'user_meta' => '{}',
        'segments' => '{}',
        'extra_fields' => '{}',
        'emit_events' => 'false'
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def http_method
      HTTP_METHOD
    end

    form_configurable :protocol, type: :array, values: PROTOCOLS
    form_configurable :domain, roles: :completable
    form_configurable :organization_subdomain
    form_configurable :auth_token
    form_configurable :comment
    form_configurable :score
    form_configurable :kind
    form_configurable :stream
    form_configurable :created_at
    form_configurable :user_meta, type: :text, ace: true
    form_configurable :segments, type: :text, ace: true
    form_configurable :extra_fields, type: :text, ace: true
    form_configurable :emit_events, :array, values: %w(true false)
    form_configurable :expected_receive_period_in_days

    def complete_domain
      DOMAINS
    end

    def validate_options
      if options['protocol'].blank? || !PROTOCOLS.include?(options['protocol'])
        errors.add(:base, "The 'protocol' option is required and must be set to 'http' or 'https'")
      end
      if options['domain'].blank?
        errors.add(:base, "The 'domain' option is required.")
      end
      if options['organization_subdomain'].blank?
        errors.add(:base, "The 'organization_subdomain' option is required.")
      end
      if options['auth_token'].blank?
        errors.add(:base, "The 'auth_token' option is required.")
      end
      if options['expected_receive_period_in_days'].blank?
        errors.add(:base, "The 'expected_receive_period_in_days' option is required.")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      validate_web_request_options!
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          outgoing = interpolated.slice(*BASIC_OPTIONS)
          outgoing.merge!(interpolated['extra_fields'].presence || {})

          handle outgoing, event, headers(auth_header(interpolated['auth_token']))
        end
      end
    end

    def check
      outgoing = interpolated.slice(*BASIC_OPTIONS)
      outgoing.merge!(interpolated['extra_fields'].presence || {})

      handle outgoing, headers(auth_header(interpolated['auth_token']))
    end

    private

    def normalize_response_headers(headers)
      case interpolated['event_headers_style']
      when nil, '', 'capitalized'
        normalize = ->name {
          name.gsub(/(?:\A|(?<=-))([[:alpha:]])|([[:alpha:]]+)/) {
            $1 ? $1.upcase : $2.downcase
          }
        }
      when 'downcased'
        normalize = :downcase.to_proc
      when 'snakecased', nil
        normalize = ->name { name.tr('A-Z-', 'a-z_') }
      when 'raw'
        normalize = ->name { name }  # :itself.to_proc in Ruby >= 2.2
      else
        raise ArgumentError, "if provided, event_headers_style must be 'capitalized', 'downcased', 'snakecased' or 'raw'"
      end

      headers.each_with_object({}) { |(key, value), hash|
        hash[normalize[key]] = value
      }
    end

    def post_url(event = Event.new)
      event_options = interpolated(event.payload)
      protocol = event_options['protocol']
      host = "#{event_options['organization_subdomain']}.#{event_options['domain']}"

      "#{protocol}://#{host}#{API_ENDPOINT}"
    end

    def auth_header(token)
      { "Authorization" => "Bearer #{token}" }
    end

    def handle(data, event = Event.new, headers)
      url = post_url(event)
      headers['Content-Type'] = 'application/json; charset=utf-8'
      body = data.to_json

      response = faraday.run_request(http_method.to_sym, url, body, headers)
      return unless boolify(interpolated['emit_events'])

      create_event(payload: { body: response.body,
                              headers: normalize_response_headers(response.headers),
                              status: response.status })
    end
  end
end
