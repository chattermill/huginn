module Agents
  class ZendeskSatisfactionRatingsAgent < WebsiteAgent
    include FormConfigurable

    API_ENDPOINT = "/api/v2/satisfaction_ratings.json"
    DOMAIN = "zendesk.com"

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule "every_12h"

    before_validation :build_default_options

    form_configurable :subdomain
    form_configurable :filter
    form_configurable :auth_token
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :retrieve_assignee, type: :array, values: %w(true false)
    form_configurable :retrieve_ticket, type: :array, values: %w(true false)
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'subdomain' => 'myaccount',
        'filter' => 'sort_order=desc&score=received_with_comment',
        'auth_token' => '{% credential ZendeskCredential %}',
        'expected_update_period_in_days' => '2',
        'mode' => 'on_change',
        'retrieve_assignee' => 'true',
        'retrieve_ticket' => 'true'
      }
    end

    private

    def build_default_options
      options['url'] = "https://#{options['subdomain']}.#{DOMAIN}#{API_ENDPOINT}"
      options['url'] << "?#{options['filter']}" if options['filter'].present?
      options['headers'] = auth_header(options['auth_token'])
      options['type'] = 'json'
    end

    def auth_header(token)
      { "Authorization" => "Basic #{token}" }
    end

    def parse(data)
      parsed_data = JSON.parse(data)
      parsed_data['satisfaction_ratings'].map! do |rating|
        rating.merge!(get_assignee(rating['assignee_id'])) if retrieve_assignee?
        rating.merge!(get_ticket(rating['ticket_id'])) if retrieve_ticket?
        rating
      end

      parsed_data
    end

    def retrieve_assignee?
      boolify(interpolated['retrieve_assignee'])
    end

    def retrieve_ticket?
      boolify(interpolated['retrieve_ticket'])
    end

    def get_assignee(assignee_id)
      log "Fetching assiginee #{assignee_id}"
      uri = "#{zendesk_uri_base}/users/#{assignee_id}.json"
      get_zendesk_resource(uri)
    end

    def get_ticket(ticket_id)
      log "Fetching ticket #{ticket_id}"
      uri = "#{zendesk_uri_base}/tickets/#{ticket_id}.json"
      get_zendesk_resource(uri)
    end

    def zendesk_uri_base
      "https://#{interpolated['subdomain']}.#{DOMAIN}/api/v2"
    end

    def get_zendesk_resource(uri)
      response = faraday.get(uri)
      return unless response.success?

      JSON.parse(response.body)
    end
  end
end
