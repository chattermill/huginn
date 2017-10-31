module Agents
  class TrustPilotAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    CHATTERMILL_HUGINN_DOMAIN = "https://huginn.chattermill.xyz"
    TRUSTPILOT_URL_BASE = "https://api.trustpilot.com/v1"
    TRUSTPILOT_URL_AUTHENTICATE = "https://authenticate.trustpilot.com"
    UNIQUENESS_LOOK_BACK = 500

    can_dry_run!
    cannot_receive_events!

    default_schedule 'every_1d'

    description do
      <<-MD
        TrustPilot Agent fetches reviews from the TrustPilot API given client's access details and a list of Business Unit.

        Options:

          * `api_key` - TrustPilot Api Key.
          * `api_secret` - TrustPilot Api Secret.
          * `business_units_ids` - Specify the list of Business Units IDs for which Huginn will retrieve reviews.
          * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
          * `expected_update_period_in_days` - Specify the period in days used to calculate if the agent is working.
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "id": "59883aebfba87f08a8274e07",
          "stars": 5,
          "text": "Hello World",
          "title": "Hello World …",
          "language": "en",
          "created_at": "2017-08-07T10:03:23Z",
          "updated_at": "2017-08-07T10:03:23Z,
          "company_reply": nil,
          "is_verified": false,
          "number_of_likes": 0,
          "status": "active",
          "report_data": nil,
          "compliance_labels": [],
          "consumer_name": "Jeffry Taraca",
          "consumer_location": "Kirkeby, DK"
        }
    MD

    form_configurable :api_key
    form_configurable :api_secret
    form_configurable :business_units_ids
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :secret
    form_configurable :access_token
    form_configurable :refresh_token
    form_configurable :access_token_expires_at
    form_configurable :expected_update_period_in_days

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        'api_key' => '{% credential TrustPilotApiKey %}',
        'api_secret' => '{% credential TrustPilotApiSecret %}',
        'mode' => 'on_change',
        'secret' => SecureRandom.hex(12),
        'expected_update_period_in_days' => '1'
      }
    end

    def validate_options
      %w[api_key api_secret].each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      if options['secret'].blank?
        errors.add(:base, "Must specify a secret for 'Authenticating' requests")
      end

      if options['business_units_ids'].blank?
        errors.add(:base, "The 'business_units_ids' option is required.")
      end

      if options['expected_update_period_in_days'].blank?
        errors.add(:base, "The 'expected_update_period_in_days' option is required.")
      end

      validate_web_request_options!
    end

    def headers(_ = {})
      { "Authorization" => "Bearer #{access_token}"}
    end

    def check
      prepare_request!
      if authorized?
        reviews = business_units.map(&:parse_reviews).flatten
        reviews.each do |review|
          if store_payload!(review)
            log "Storing new result for '#{name}': #{review.inspect}"
            create_event payload: review
          end
        end
      else
        log "Not Authorized"
      end
    end

    def receive_web_request(params, method, format)
      log "Params: #{params} | Method: #{method} | format: #{format}"

      secret = params.delete('secret')
      return ["Not Authorized", 401] unless secret == interpolated['secret']

      # TODO get access_token, refresh_token and expires_at
    end

    private

    def business_units
      @business_units ||= business_units_ids.map do |bid|
        business_unit = fetch_reviews(bid)
        TrustPilotParser.new(business_unit)
      end
    end

    def business_units_ids
      @business_units_ids ||= interpolated['business_units_ids'].split(',').map(&:strip)
    end

    def fetch_reviews(business_unit_id)
      log "Fetching business unit: ##{business_unit_id} private reviews"
      url = "#{TRUSTPILOT_URL_BASE}/private/business-units/#{business_unit_id}/reviews"
      fetch_resource(url)
    end

    def fetch_resource(uri)
      response = faraday.get(uri)
      unless response.success?
        log "Fetch reviews Failed (#{response.status}) #{response.body}"
        return {}
      end

      JSON.parse(response.body)
    end

    def store_payload!(review)
      case interpolated['mode'].presence
      when 'on_change'
        review_id = review["id"]
        if  old_events.find { |event| event.payload["id"] == review_id }
          false
        else
          true
        end
      when 'all', 'merge', ''
        true
      else
        raise "Illegal options[mode]: #{interpolated['mode']}"
      end
    end

    def old_events
      @old_events ||= events.order('id desc').limit(UNIQUENESS_LOOK_BACK)
    end

    def prepare_request!
      if authorized?
        expires_at = interpolated['access_token_expires_at']
        if expires_at && Time.now > expires_at.to_datetime
          refresh_token!
        end
      else
        trustpilot_authenticate!
      end
    end

    def refresh_token!
      log "Refresh token"
      body = { grant_type: 'refresh_token',
               refresh_token: interpolated['refresh_token'] }
      response = faraday.run_request(:post, refresh_token_url, body, basic_auth_headers)

      data = JSON.parse(response.body)
      if response.status == 200
        expires_at = (Time.now + data['expires_in'].to_i).iso8601
        new_options = options.merge(access_token_expires_at: expires_at,
                                    access_token: data['access_token'],
                                    refresh_token: data['refresh_token'])

        update(options: new_options)
      else
        log "Refresh token failed (#{response.status}) - #{response.body}"
      end
    end

    def trustpilot_authenticate!
      response = faraday.get(authenticate_url, authenticate_options)
      log "Failed authenticate (#{response.status}) #{response.body}" unless response.status == 200
    end

    def authorized?
      interpolated['access_token'].present?
    end

    def basic_auth_headers
      { 'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': "Basic #{basic_auth}" }
    end

    def basic_auth
      Base64.strict_encode64("#{api_key}:#{api_secret}")
    end

    def authenticate_options
      {
        client_id: api_key,
        redirect_uri: webhook_redirect_url,
        response_type: 'code'
      }
    end

    def authenticate_url
      TRUSTPILOT_URL_AUTHENTICATE
    end

    def refresh_token_url
      "#{TRUSTPILOT_URL_BASE}/oauth/oauth-business-users-for-applications/refresh"
    end

    def webhook_redirect_url
      "#{CHATTERMILL_HUGINN_DOMAIN}/users/#{user_id}/web_requests/#{id}/#{interpolated['secret']}"
    end

    def access_token
      interpolated['access_token']
    end

    def api_key
      interpolated['api_key']
    end

    def api_secret
      interpolated['api_secret']
    end
  end
end
