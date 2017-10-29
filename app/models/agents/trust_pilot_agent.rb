module Agents
  class TrustPilotAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    HTTP_METHOD = "get"
    TRUSTPILOT_URL_BASE = "https://api.trustpilot.com/v1"
    UNIQUENESS_LOOK_BACK = 500

    can_dry_run!
    no_bulk_receive!

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
    form_configurable :expected_update_period_in_days

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        'api_key' => '{% credential TrustPilotApiKey %}',
        'api_secret' => '{% credential TrustPilotApiSecret %}',
        'mode' => 'on_change',
        'expected_update_period_in_days' => '1'
      }
    end

    def validate_options
      super

      %w[api_key api_secret].each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      if options['business_units_ids'].blank?
        errors.add(:base, "The 'business_units_ids' option is required.")
      end
    end

    def check
      reviews = business_units.map(&:parse_reviews).flatten
      reviews.each do |review|
        if store_payload!(review)
          log "Storing new result for '#{name}': #{review.inspect}"
          create_event payload: review
        end
      end
    end

    private

    def headers(_ = {})
      { "apikey" => "#{interpolated['api_key']}" }
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

    def business_units
      @business_units ||= business_units_ids.map do |bid|
        business_unit = fetch_private_reviews(bid)
        TrustPilotParser.new(business_unit)
      end
    end

    def business_units_ids
      @business_units_ids ||= interpolated['business_units_ids'].split(',').map(&:strip)
    end

    def fetch_private_reviews(business_unit_id)
      # TODO: change to private review endpoint, need oauth
      log "Fetching business unit: ##{business_unit_id} reviews"
      url = "#{TRUSTPILOT_URL_BASE}/business-units/#{business_unit_id}/reviews"
      fetch_resource(url)
    end

    def fetch_resource(uri)
      response = faraday.get(uri)
      return {} unless response.success?

      JSON.parse(response.body)
    end
  end
end
