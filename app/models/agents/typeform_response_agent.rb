# frozen_string_literal: true

module Agents
  class TypeformResponseAgent < Agent
    include FormConfigurable

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 5

    gem_dependency_check { defined?(Typeform) }

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_5h'

    description <<-MD
      Typeform Agent fetches responses from the Typeform Response API given an access token.

      In the `on_change` mode, change is detected based on the resulted event payload after applying this option.
      If you want to add some keys to each event but ignore any change in them, set `mode` to `all` and put a DeDuplicationAgent downstream.
      If you specify `merge` for the `mode` option, Huginn will retain the old payload and update it with new values.

      Options:

        * `access_token` - Typeform API Key.
        * `form_id` - Typeform Form ID.
        * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
        * `guess_mode` - Let the agent try to figure out the score question and the comment question automatically using the first `opinionscale` question and the first `textarea` question
        * `score_question_ids` - Hard-code the comma separated list of ids of the score questions (agent will pick the first one present) if `guess_mode` is off
        * `comment_question_ids` - Hard-code he comma separated list of ids of the comment questions (agent will pick the first one present) if `guess_mode` is off
        * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
        * `limit` - Number of responses to fetch per run, better to set to a low number and have the agent run more often.
        * `since` - Specify date and time, to limit request to responses submitted since the specified date and time, e.g. `8 hours ago`, `may 27th` [more valid formats](https://github.com/mojombo/chronic).
        * `until` - Specify date and time, to limit request to responses submitted until the specified date and time, e.g. `1979-05-27 05:00:00`, `January 5 at 7pm` [more valid formats](https://github.com/mojombo/chronic).
    MD

    event_description <<-MD
      Events look like this:
        {
          "score": 9,
          "comment": "Love the concept and the food! Just a little too expensive.",
          "id": "62e3caeaca5100adf84f61708ad69960",
          "created_at": "2017-08-12 19:16:02",
          "answers": {
            {
               "field": {
                 "id": "58048684",
                 "type": "opinion_scale"
               },
               "type": "number",
               "number": 3
             },
             {
               "field": {
                 "id": "58049393",
                 "type": "multiple_choice"
               },
               "type": "choice",
               "choice": {
                 "label": "55 to 64"
               }
             },
             {
               "field": {
                 "id": "58049487",
                 "type": "dropdown"
               },
               "type": "text",
               "text": "South East"
             },
             {
               "field": {
                 "id": "58049969",
                 "type": "long_text"
               },
               "type": "text",
               "text": "It is really helpful to see your credit score at any time and if it changes then why gas it changed"
             }
          },
          "metadata": {
            "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_3 like Mac OS X) AppleWebKit/603.3.8 (KHTML, like Gecko) Version/10.0 Mobile/14G60 Safari/602.1",
            "platform": "mobile",
            "referer": "https://typeform.com/to/XXXX",
            "network_id": "8f548786ca",
            "browser": "touch"
          },
          "hidden_variables": {
            "customer": "11223",
            "name": "Susan",
            "score": "2",
            "survey_answer": "Somewhat+disappointed",
            "survey_name": "login_monthly"
          }
        }
    MD

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    form_configurable :access_token
    form_configurable :form_id
    form_configurable :guess_mode, type: :boolean
    form_configurable :score_question_ids
    form_configurable :comment_question_ids
    form_configurable :limit
    form_configurable :since
    form_configurable :until
    form_configurable :mode, type: :array, values: %w[all on_change merge]
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'access_token' => '{% credential TypeformAccessToken %}',
        'guess_mode' => true,
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change',
        'limit' => 20
      }
    end

    def validate_options
      super

      %w[access_token form_id].each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      %w[since until].each do |key|
        if options[key].present?
          date = Chronic.parse(options[key])
          errors.add(:base, "The '#{key}' option has an invalid format") if date.nil?
        end
      end
    end

    def check
      typeform_events.each do |e|
        if store_payload!(previous_payloads(1), e)
          log "Storing new result for '#{name}': #{e.inspect}"
          create_event payload: e
        end
      end
    end

    private

    def previous_payloads(num_events)
      # Larger of UNIQUENESS_FACTOR * num_events and UNIQUENESS_LOOK_BACK
      look_back = UNIQUENESS_FACTOR * num_events
      look_back = UNIQUENESS_LOOK_BACK if look_back < UNIQUENESS_LOOK_BACK

      events.order('id desc').limit(look_back) if interpolated['mode'] == 'on_change'
    end

    # This method returns true if the result should be stored as a new event.
    # If mode is set to 'on_change', this method may return false and update an
    # existing event to expire further in the future.
    # Also, it will retrive asignee and/or ticket if the event should be stored.
    def store_payload!(old_events, result)
      case interpolated['mode'].presence
      when 'on_change'
        result_json = result.to_json
        if found = old_events.find { |event| event.payload.to_json == result_json }
          found.update!(expires_at: new_event_expiration_date)
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

    def typeform_events
      typeform.complete_entries(params).items.map { |r| transform_typeform_responses(r) }
    end

    def transform_typeform_responses(response)
      {
        score: score_from_response(response),
        comment: comment_from_response(response),
        created_at: response.submitted_at,
        id: response.token,
        answers: response.answers,
        metadata: response.metadata,
        hidden_variables: response.hidden
      }
    end

    def score_from_response(response)
      answer = if boolify(interpolated['guess_mode'])
                 response.answers.find {|h| h.field.type == "opinion_scale" }
               else
                 answer_for(response, interpolated['score_question_ids'])
               end

      answer.number if answer.present?
    end

    def comment_from_response(response)
      answer = if boolify(interpolated['guess_mode'])
                 response.answers.find { |h| h["field"]["type"] == "long_text" }
               else
                 answer_for(response, interpolated['comment_question_ids'])
               end

      answer.text if answer.present?
    end

    def answer_for(response, option_ids)
      answers_ids = response.answers.map {|a| a.field.id }
      key = option_ids.split(',').find { |id| answers_ids.include?(id) }
      response.answers.find {|h| h.field.id == key }
    end

    def params
      hash = {
        'order_by[]' => 'date_submit,desc',
        'page_size' => interpolated['limit']
      }

      %w[since until].each do |key|
        if interpolated[key].present?
          date = Chronic.parse(interpolated[key])
          hash.merge!(key => date.strftime('%Y-%m-%dT%H:%M:%S')) unless date.nil?
        end
      end

      hash
    end

    def typeform
      @typeform ||= Typeform::Response.new(access_token: interpolated['access_token'], form_id: interpolated['form_id'])
    end
  end
end
