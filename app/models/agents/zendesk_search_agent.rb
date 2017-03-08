module Agents
  class ZendeskSearchAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    HTTP_METHOD = "get"
    API_ENDPOINTS = {
      "users" => "/api/v2/users",
      "tickets" => "/api/v2/tickets",
      "organizations" => "/api/v2/organizations"
    }
    DOMAIN = "zendesk.com"

    can_dry_run!
    no_bulk_receive!
    cannot_be_scheduled!

    description do
      <<-MD
        The Zendesk Search Agent receives events, find Zendesk resources and emit an event with the result.

        A Zendesk Search Agent can receives events from other agents, search resources by `id` (Users, Tickets and Organizations)
        and emit the result as an `event` with the data merged to the original payload if `merge` option is `true`.
        If the request fails, a notification to Slack will be sent.

        When `merge` is `true` search data is added to the event payload under the key `zendesk_search`.

        Options:

          * `subdomain` - Specify the subdomain of the Zendesk client (e.g `moo` or `hellofresh`).
          * `auth_token` - Specify the token to be used for Basic authentication. Please, DO NOT include the `Basic` word, just the hash.
          * `resource` - Select the resource type to find (`users`, `tickets`, `organizations`).
          * `id` - Specify the Liquid interpolated expresion to get the `id` of the Zendesk user to find.
          * `merge` - Select `true` or `false`.
          * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "status": 200,
          "data": "{...}"
        }
    MD

    def default_options
      {
        'subdomain' => 'myaccount',
        'auth_token' => '{% credential ZendeskCredential %}',
        'resource' => 'users',
        'id' => '{{ data.assignee_id }}',
        'merge' => 'true',
        'expected_receive_period_in_days' => '1'
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def http_method
      HTTP_METHOD
    end

    form_configurable :subdomain
    form_configurable :auth_token
    form_configurable :resource, type: :array, values: API_ENDPOINTS.keys
    form_configurable :id
    form_configurable :merge, type: :array, values: %w(true false)
    form_configurable :expected_receive_period_in_days

    def validate_options
      %w(subdomain auth_token id expected_receive_period_in_days).each do |key|
        if options[key].blank?
          errors.add(:base, "The '#{key}' option is required.")
        end
      end

      unless options['resource'].in?(API_ENDPOINTS.keys)
        valid_resources = API_ENDPOINTS.keys.to_sentence(last_word_connector: ' or ')
        errors.add(:base, "The 'resource' option must be #{valid_resources}.")
      end

      if boolify(options['merge']).nil?
        errors.add(:base, "The 'merge' option must be true or false")
      end

      validate_web_request_options!
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          handle interpolated, event, headers(auth_header(interpolated['auth_token']))
        end
      end
    end

    def check
      handle interpolated, headers(auth_header(interpolated['auth_token']))
    end

    private

    def request_url(event = Event.new)
      event_options = interpolated(event.payload)
      endpoint = API_ENDPOINTS[event_options['resource']]
      host = "#{event_options['subdomain']}.#{DOMAIN}"

      "https://#{host}#{endpoint}/#{event_options['id']}.json"
    end

    def auth_header(token)
      { "Authorization" => "Basic #{token}" }
    end

    def handle(data, event = Event.new, headers)
      url = request_url(event)
      headers['Content-Type'] = 'application/json; charset=utf-8'
      response = faraday.run_request(http_method.to_sym, url, nil, headers)

      data = if boolify(interpolated['merge'])
               event.payload.merge(zendesk_search: response.body)
             else
               response.body
             end

      send_slack_notification(response, event) unless response.status == 200
      create_event(payload: { data: data, status: response.status })
    end

    def send_slack_notification(response, event)
      link = "<https://huginn.chattermill.xyz/agents/#{event.agent_id}/events|Details>"
      parsed_body = JSON.parse(response.body) rescue ""
      description = "Hi! I'm reporting a problem with the Zendesk Search agent *#{name}*"
      message = "#{description} - #{link}\n`HTTP Status: #{response.status}`\n```#{parsed_body}```"
      slack_opts = { icon_emoji: ':fire:', channel: ENV['SLACK_CHANNEL'] }

      slack_notifier.ping message, slack_opts
    end

    def slack_notifier
      @slack_notifier ||= Slack::Notifier.new(ENV['SLACK_WEBHOOK_URL'], username: 'Huginn')
    end
  end
end
