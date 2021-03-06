# frozen_string_literal: true

module Agents
  class ChattermillResponseAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    default_schedule "never"

    API_ENDPOINT = "/webhooks/responses"
    MAX_COUNTER_TO_EXPIRE_BATCH = 3
    DOMAINS = {
      production: "app.chattermill.xyz",
      development: "lvh.me:3000",
      test: "localhost:3000"
    }

    can_dry_run!
    no_bulk_receive!

    before_validation :parse_json_options

    description do
      <<-MD
        The Chattermill Response Agent receives events, build responses, and sends the results using the Chattermill API.

        A Chattermill Response Agent can receives events from other agents or run periodically,
        it builds Chattermill Responses with the [Liquid-interpolated](https://github.com/cantino/huginn/wiki/Formatting-Events-using-Liquid)
        contents of `options`, and sends the results as Authenticated POST requests to a specified API instance.
        If the request fail, a notification to Slack will be sent.

        If `emit_events` is set to `true`, the server response will be emitted as an Event and can be fed to a
        WebsiteAgent for parsing (using its `data_from_event` and `type` options). No data processing
        will be attempted by this Agent, so the Event's "body" value will always be raw text.
        The Event will also have a "headers" hash and a "status" integer value.
        Header names are capitalized; e.g. "Content-Type".

        If `send_batch_events` is set to `true`, the agent collects any events sent to it and sends them in batch of number setted
        in `max_events_per_batch`.

        Options:

          * `organization_subdomain` - Specify the subdomain for the target organization (e.g `moo` or `hellofresh`).
          * `comment` - Specify the Liquid interpolated expresion to build the Response comment.
          * `score` - Specify the Liquid interpolated expresion to build the Response score.
          * `data_type` - Specify the Liquid interpolated expresion to build the Response data_type.
          * `data_source` - Specify the Liquid interpolated expresion to build the Response data_source.
          * `dataset_id` - Specify the Liquid interpolated expresion to build the Response dataset_id. This takes precedence over `data_type` and `data_source`.
          * `created_at` - Specify the Liquid interpolated expresion to build the Response created_at date.
          * `user_meta` - Specify the Liquid interpolated JSON to build the Response user metas.
          * `segments` - Specify the Liquid interpolated JSON to build the Response segments.
          * `extra_fields` - Specify the Liquid interpolated JSON to build additional fields for the Response, e.g: `{ approved: true }`.
          * `mappings` - Specify the mapping definition object where any field can be mapped with a single value.
          * `bucketing_object` - Specify the bucketing definition object where any field can be broken into a specific bucket.
          * `emit_events` - Select `true` or `false`.
          * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
          * `send_batch_events` - Select `true` or `false`.
          * `max_events_per_batch` - Specify the maximum number of events that you'd like to send per batch.

          If you specify `mappings` you must set up something like this:

              "score": {
                "Good, I'm satisfied": "10",
                "Bad, I'm unsatisfied": "0"
              },
              "segments.segment_id.value": {
                "Joyeux Noël": "651",
                "Lux Letterbox Subscription": "669"
              }

      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "status": 201,
          "headers": {
            "Content-Type": "'application/json",
            ...
          },
          "body": "{...}"
        }
    MD

    def default_options
      sample_hash = Utils.pretty_jsonify(
        sample_id: { type: "text", name: "Sample Id", value: "{{data.sample_id}}" }
      )

      {
        'comment' => '{{ data.comment }}',
        'score' => '{{ data.score }}',
        'data_type' => 'nps',
        'data_source' => 'nps_survey',
        'created_at' => '{{ data.date }}',
        'user_meta' => sample_hash,
        'segments' => sample_hash,
        'extra_fields' => '{}',
        'mappings' => '{}',
        'bucketing' => '{}',
        'emit_events' => 'true',
        'expected_receive_period_in_days' => '1',
        'send_batch_events' => 'true',
        'max_events_per_batch' => 30
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def http_method
      id? ? :patch : :post
    end

    form_configurable :organization_subdomain
    form_configurable :id
    form_configurable :comment
    form_configurable :score
    form_configurable :data_type
    form_configurable :data_source
    form_configurable :dataset_id
    form_configurable :created_at
    form_configurable :user_meta, type: :json, ace: { mode: 'json' }
    form_configurable :segments, type: :json, ace: { mode: 'json' }
    form_configurable :extra_fields, type: :json, ace: { mode: 'json' }
    form_configurable :mappings, type: :json, ace: { mode: 'json' }
    form_configurable :bucketing, type: :json, ace: { mode: 'json' }
    form_configurable :emit_events, type: :boolean
    form_configurable :expected_receive_period_in_days
    form_configurable :send_batch_events, type: :boolean
    form_configurable :max_events_per_batch

    def validate_options
      if options['organization_subdomain'].blank?
        errors.add(:base, "The 'organization_subdomain' option is required.")
      end

      if options['dataset_id'].blank? && new_record?
        errors.add(:base, "The 'dataset_id' option is required.")
      end

      if options['expected_receive_period_in_days'].blank?
        errors.add(:base, "The 'expected_receive_period_in_days' option is required.")
      end

      if options.key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      if options.key?('send_batch_events') && boolify(options['send_batch_events']).nil?
        errors.add(:base, "if provided, send_batch_events must be true or false")
      end

      if options.key?('send_batch_events') && boolify(options['send_batch_events']) && schedule == 'never'
        errors.add(:base, "Set a schedule value different than 'Never'")
      end

      if options.key?('send_batch_events') && !boolify(options['send_batch_events']) && (schedule != 'never')
        errors.add(:base, "Schedule must be 'Never'")
      end

      if options.key?('send_batch_events') && boolify(options['send_batch_events']) && (options['max_events_per_batch'].blank? || !options['max_events_per_batch']&.to_i&.positive?)
        errors.add(:base, "The 'max_events_per_batch' option is required and must be an integer greater than 0")
      end

      validate_web_request_options!
    end

    def receive(incoming_events)
      return save_events_in_buffer(incoming_events) if batch_events?

      incoming_events.each do |event|
        interpolate_with(event) do
          handle outgoing_data, event, headers(auth_header)
        end
      end
    end

    def check
      if batch_events?
        if process_queue?
          process_queue!
          handle_batch batch_events_payload, headers(auth_header)
        elsif !queue_in_process? && memory['events']&.length&.positive?
          memory['check_counter'] = (memory['check_counter']&.to_i || 0) + 1
        end
      end
    end

    private

    def handle(data, event = Event.new, headers)
      return unless valid_payload?(data, event)
      headers['Content-Type'] = 'application/json; charset=utf-8'

      response = faraday.run_request(http_method, request_url, data.to_json, headers)
      emit_event(response, event, response.headers)
    rescue Faraday::TimeoutError
      response = OpenStruct.new body: "Request timeout", status: 408, headers: headers
      emit_event(response, event, response.headers)
    end

    def outgoing_data
      Chattermill::ResponseParser.new(interpolated).parse
    end

    def emit_event(response, event, headers)
      return unless boolify(interpolated['emit_events'])

      create_event(event_payload(response, headers, event))
      send_slack_notification(response, event) unless [200, 201].include?(response.status)
    end

    def save_events_in_buffer(incoming_events)
      memory['events'] ||= []

      incoming_events.each do |event|
        memory['events'] << event.id
      end
    end

    def batch_events_payload
      payloads = []
      source_events.each do |event|
        interpolate_with(event) do
          data = outgoing_data
          payloads.push(data) if valid_payload?(data, event)
        end
      end

      { responses: payloads }
    end

    def source_events
      @source_events ||= Event.where(id: events_ids).reorder(id: :asc)
    end

    def handle_batch(data, headers)
      return if data[:responses].empty?

      headers['Content-Type'] = 'application/json; charset=utf-8'
      response = faraday.run_request(:post, request_url(batch: true), data.to_json, headers)
      headers = normalize_response_headers(response.headers)

      emit_events(response)
    rescue Faraday::TimeoutError
      response = OpenStruct.new body: "Request timeout", status: 408, headers: headers
      source_events.each do |event|
        emit_event(response, event, headers)
      end
    ensure
      memory['in_process'] = false
      memory['check_counter'] = 0
    end

    def emit_events(response)
      return unless boolify(interpolated['emit_events'])

      if [200, 201].include?(response.status)
        responses = JSON.parse(response.body)
        responses.each_with_index do |r, i|
          event = source_events.detect{ |e| e.id == events_ids[i] }
          event_response = OpenStruct.new(r)

          emit_event(event_response, event, headers)
        end
      else
        source_events.each do |event|
          emit_event(response, event, headers)
        end
      end
    end

    def event_payload(response, headers, event)
      { payload: { body: response.body,
                   headers: normalize_response_headers(headers),
                   status: response.status,
                   source_event: event.id } }
    end

    def request_url(batch: false)
      protocol = Rails.env.production? ? 'https' : 'http'
      domain = DOMAINS[Rails.env.to_sym]
      if batch
        "#{protocol}://#{domain}#{API_ENDPOINT}/bulk"
      else
        "#{protocol}://#{domain}#{API_ENDPOINT}/#{interpolated['id']}"
      end
    end

    def normalize_response_headers(headers)
      case interpolated['event_headers_style']
      when nil, '', 'capitalized'
        normalize = ->(name) {
          name.gsub(/(?:\A|(?<=-))([[:alpha:]])|([[:alpha:]]+)/) {
            $1 ? $1.upcase : $2.downcase
          }
        }
      when 'downcased'
        normalize = :downcase.to_proc
      when 'snakecased'
        normalize = ->(name) { name.underscore }
      when 'raw'
        normalize = ->(name) { name } # :itself.to_proc in Ruby >= 2.2
      else
        raise ArgumentError, "if provided, event_headers_style must be 'capitalized', 'downcased', 'snakecased' or 'raw'"
      end

      headers.each_with_object({}) { |(key, value), hash| hash[normalize[key]] = value }
    end

    def parse_json_options
      parse_json_option('user_meta')
      parse_json_option('segments')
      parse_json_option('extra_fields')
      parse_json_option('mappings')
      parse_json_option('bucketing')
    end

    def parse_json_option(key)
      options[key] = JSON.parse(options[key]) unless options[key].is_a?(Hash)
    rescue
      errors.add(:base, "The '#{key}' option is an invalid JSON.")
    end

    def id?
      interpolated['id'].present?
    end

    def auth_header
      {
        "Authorization" => "Bearer #{ENV['CHATTERMILL_AUTH_TOKEN']}",
        "Organization" => interpolated['organization_subdomain']
      }
    end

    def valid_payload?(data, event)
      validator = ResponseValidator.new(data)
      error(validator.errors.messages.merge(source_event: event.id).to_json) unless validator.valid?

      validator.valid?
    end

    def queue_in_process?
      boolify(memory['in_process']) == true
    end

    def process_queue!
      memory['in_process'] = true
      save!
    end

    def process_queue?
      !queue_in_process? && (batch_ready? || batch_expired?)
    end

    def batch_ready?
      memory['events'] && memory['events'].length >= interpolated['max_events_per_batch'].to_i
    end

    def batch_expired?
      counter = memory['check_counter']&.to_i || 0
      memory['events']&.length&.positive? && counter >= MAX_COUNTER_TO_EXPIRE_BATCH
    end

    def batch_events?
      boolify(interpolated['send_batch_events'])
    end

    def events_ids
      @events_ids ||= memory['events'].shift(interpolated['max_events_per_batch'].to_i)
    end

    def send_slack_notification(response, event)
      description = slack_description(response, event)

      slack_opts = {
        icon_emoji: ':fire:',
        channel: ENV['SLACK_CHANNEL'],
        attachments: [
          {
            title: "Error #{response.status} on #{name}",
            author_name: event.agent&.name,
            color: "danger",
            text: description,
            fallback: description,
            mrkdwn_in: [
              "text"
            ]
          }
        ]
      }

      slack_notifier.ping('', slack_opts)
    end

    def slack_description(response, event)
      link = "<https://huginn.chattermill.xyz/agents/#{event.agent_id}/events|Details>"
      source_event_link = "<https://huginn.chattermill.xyz/events/#{event.id}|Source event>"
      parsed_body = JSON.parse(response.body) rescue response.body

      details = "\n#{source_event_link} | #{link}"
      "```#{parsed_body}```#{details if event.id.present?}"
    end

    def slack_notifier
      @slack_notifier ||= Slack::Notifier.new(ENV['SLACK_WEBHOOK_URL'], username: 'Huginn')
    end

    class ResponseValidator
      include ActiveModel::Validations

      attr_reader :data

      validates :score, presence: true, numericality: true, if: :validate_score?

      def initialize(data)
        @data = data
      end

      def data_type
        data['data_type']
      end

      def score
        data['score']
      end

      private

      def validate_score?
        data_type.in?(%w[nps review csat])
      end
    end
  end
end
