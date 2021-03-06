module Agents
  class SurveyMonkeyAgent < Agent
    include WebRequestConcern
    include FormConfigurable
    include DeduplicationConcern

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 1
    HTTP_METHOD = "get".freeze
    SURVEYS_URL_BASE = "https://api.surveymonkey.net/v3/surveys".freeze

    can_dry_run!
    no_bulk_receive!
    can_order_created_events!

    default_schedule "every_12h"

    description do
      <<-MD
        The Survey Monkey Agent pull surveys responses via [SurveyMonkey API](https://developer.surveymonkey.com/api/v3/#surveys-id-responses-bulk),
        extract a `comment` and calculates a `score` based on available questions, then it sends the results as events.

        With `on_change` mode selected, changes are detected based on the resulted event payload after applying this option.
        If you want to add some keys to each event but ignore any change in them, set `mode` to `all` and put a DeDuplicationAgent downstream.
        If you specify `merge` for the `mode` option, Huginn will retain the old payload and update it with new values.

        Options:

          * `api_token` - Specify the SurveyMonkey API token for authentication.
          * `survey_ids` - Specify the list of survey IDs for which Huginn will retrieve responses.
          * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
          * `guess_mode` - Let the agent try to figure out the score question and the comment question automatically.
          * `score_question_ids` - Hard-code the comma separated list of ids of the score questions (agent will pick the first one present) if `guess_mode` is off
          * `comment_question_ids` - Hard-code he comma separated list of ids of the comment questions (agent will pick the first one present) if `guess_mode` is off
          * `uniqueness_look_back` - Set the limit the number of events checked for uniqueness (typically for performance).  This defaults to the larger of #{UNIQUENESS_LOOK_BACK} or #{UNIQUENESS_FACTOR}x the number of detected received results.
          * `expected_update_period_in_days` - Specify the period in days used to calculate if the agent is working.
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "score": 2,
          "comment": "Sometimes the website is hanged, not so stable.",
          "response_id": "783280986",
          "survey_id": "10172078",
          "created_at": "2009-04-30T01:45:11+00:00",
          "language": "en"
        }
    MD

    def default_options
      {
        'api_token' => '{% credential SurveyMonkeyToken %}',
        'expected_update_period_in_days' => '2',
        'mode' => 'on_change',
        'page' => '1',
        'per_page' => '100',
        'guess_mode' => 'true',
        'use_weights' => 'false'
      }
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def http_method
      HTTP_METHOD
    end

    form_configurable :api_token
    form_configurable :survey_ids
    form_configurable :guess_mode, type: :boolean
    form_configurable :score_question_ids
    form_configurable :use_weights, type: :boolean
    form_configurable :comment_question_ids
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :page
    form_configurable :per_page
    form_configurable :uniqueness_look_back
    form_configurable :expected_update_period_in_days

    def validate_options
      errors.add(:base, "The 'api_token' option is required.") if options['api_token'].blank?

      if options['survey_ids'].blank?
        errors.add(:base, "The 'survey_ids' option is required.")
      end

      if options['expected_update_period_in_days'].blank?
        errors.add(:base, "The 'expected_update_period_in_days' option is required.")
      end

      if options['mode'].present?
        errors.add(:base, "mode must be set to on_change, all or merge") unless %w[on_change all merge].include?(options['mode'])
      end

      if options['page'].blank?
        errors.add(:base, "The 'page' option is required.")
      end

      if options['per_page'].blank?
        errors.add(:base, "The 'per_page' option is required.")
      end

      if options.key?('guess_mode') && !boolify(options['guess_mode'])
        errors.add(:base, "score_question_ids option is required") if options['score_question_ids'].blank?
        errors.add(:base, "comment_question_ids option is required") if options['comment_question_ids'].blank?
      end

      if options['uniqueness_look_back'].present?
        errors.add(:base, "Invalid uniqueness_look_back format") unless (options['uniqueness_look_back']).to_i.positive?
      end

      validate_web_request_options!
    end

    def check
      responses = surveys.map(&:parse_responses).flatten
      return unless responses.any?

      old_events = previous_payloads(responses.size)
      responses.each do |response|
        if store_payload?(old_events, response)
          log "Storing new result for '#{name}': #{response.inspect}"
          create_event payload: response
        end
      end
    end

    private

    def headers(_ = {})
      { "Authorization" => "bearer #{interpolated['api_token']}" }
    end

    def surveys
      @surveys ||= survey_ids.map do |survey_id|
        survey = build_survey(survey_id)
        SurveyMonkeyParser.new(survey)
      end
    end

    def survey_ids
      @survey_ids ||= interpolated['survey_ids'].split(',').map(&:strip)
    end

    def page
      interpolated['page']
    end

    def per_page
      interpolated['per_page']
    end

    def build_survey(survey_id)
      survey = fetch_survey_details(survey_id)
      survey['responses'] = fetch_survey_responses(survey_id)
      if boolify(interpolated['guess_mode']) == false
        survey['score_question_ids'] = interpolated['score_question_ids']
        survey['comment_question_ids'] = interpolated['comment_question_ids']
      end
      survey['use_weights'] = boolify(interpolated['use_weights'])
      survey
    end

    def fetch_survey_responses(survey_id)
      log "Fetching survey ##{survey_id} responses"
      url = "#{SURVEYS_URL_BASE}/#{survey_id}/responses/bulk?sort_by=date_modified&sort_order=DESC&status=completed&page=#{page}&per_page=#{per_page}"
      fetch_survey_monkey_resource(url)
    end

    def fetch_survey_details(survey_id)
      log "Fetching survey ##{survey_id} details"
      url = "#{SURVEYS_URL_BASE}/#{survey_id}/details"
      fetch_survey_monkey_resource(url)
    end

    def fetch_survey_monkey_resource(uri)
      response = faraday.get(uri)
      unless response.success?
        log "Failed #{response.status}: #{response.body}"
        return {}
      end

      JSON.parse(response.body)
    end

  end
end
