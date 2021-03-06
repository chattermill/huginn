# frozen_string_literal: true

module Agents
  class TypeformAgent < Agent
    include FormConfigurable
    include DeduplicationConcern

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 1

    gem_dependency_check { defined?(Typeform) }

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_5h'

    description <<-MD
      Typeform Agent fetches responses from the Typeform Data API given client's access details.

      In the `on_change` mode, change is detected based on the resulted event payload after applying this option.
      If you want to add some keys to each event but ignore any change in them, set `mode` to `all` and put a DeDuplicationAgent downstream.
      If you specify `merge` for the `mode` option, Huginn will retain the old payload and update it with new values.

      Options:

        * `api_key` - Typeform API Key.
        * `form_id` - Typeform Form ID.
        * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
        * `guess_mode` - Let the agent try to figure out the score question and the comment question automatically using the first `opinionscale` question and the first `textarea` question
        * `score_question_ids` - Hard-code the comma separated list of ids of the score questions (agent will pick the first one present) if `guess_mode` is off
        * `comment_question_ids` - Hard-code he comma separated list of ids of the comment questions (agent will pick the first one present) if `guess_mode` is off
        * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
        * `limit` - Number of responses to fetch per run, better to set to a low number nad have the agent run more often.
        * `offset` - Number of responses to offset by if you want to go back in the past.
        * `uniqueness_look_back` - Set the limit the number of events checked for uniqueness (typically for performance).  This defaults to the larger of #{UNIQUENESS_LOOK_BACK} or #{UNIQUENESS_FACTOR}x the number of detected received results.
    MD

    event_description <<-MD
      Events look like this:
        {
          "score": 9,
          "comment": "Love the concept and the food! Just a little too expensive.",
          "id": "62e3caeaca5100adf84f61708ad69960",
          "created_at": "2017-08-12 19:16:02",
          "answers": {
            "opinionscale_40382315": "10",
            "textarea_40382382": "Your flowers are usually lovely, but if anything has gone wrong your customer service is brilliant."
          },
          "metadata": {
            "browser": "default",
            "platform": "other",
            "date_land": "2017-08-12 19:14:42",
            "date_submit": "2017-08-12 19:16:02",
            "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_12_6) AppleWebKit/603.3.8 (KHTML, like Gecko) Version/10.1.2 Safari/603.3.8",
            "referer": "https://bloomwild.typeform.com/to/XXieGQ?email=ruth.dale@gmail.com&firstname=Ruth&pc=7&id=111073107&sub=false&subn=0",
            "network_id": "603c3b7956"
          },
          "hidden_variables": {
            "email": "ruth.dale@gmail.com",
            "firstname": "Ruth",
            "pc": "7",
            "id": "111073107",
            "sub": "false",
            "subn": "0"
          }
        }
    MD

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    form_configurable :api_key
    form_configurable :form_id
    form_configurable :guess_mode, type: :boolean
    form_configurable :score_question_ids
    form_configurable :comment_question_ids
    form_configurable :limit
    form_configurable :offset
    form_configurable :mode, type: :array, values: %w[all on_change merge]
    form_configurable :uniqueness_look_back
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'api_key' => '{% credential TypeformApiKey %}',
        'guess_mode' => true,
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change',
        'limit' => 20,
        'offset' => 0
      }
    end

    def validate_options
      super

      %w[api_key form_id].each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      if options['expected_update_period_in_days'].present?
        errors.add(:base, "Invalid expected_update_period_in_days format") unless options['expected_update_period_in_days'].to_i.positive?
      end

      if options['uniqueness_look_back'].present?
        errors.add(:base, "Invalid uniqueness_look_back format") unless (options['uniqueness_look_back']).to_i.positive?
      end
    end

    def check
      if typeform_events.any?
        old_events = previous_payloads(typeform_events.size)
        typeform_events.each do |e|
          if store_payload?(old_events, e)
            log "Storing new result for '#{name}': #{e.inspect}"
            create_event payload: e
          end
        end
      end
    end

    private

    def typeform_events
      @typeform_events ||= typeform.complete_entries(params).responses.map { |r| transform_typeform_responses(r) }
    end

    def transform_typeform_responses(response)
      {
        score: score_from_response(response),
        comment: comment_from_response(response),
        created_at: response.metadata.date_submit,
        id: response.token,
        answers: response.answers,
        metadata: response.metadata,
        hidden_variables: response.hidden
      }
    end

    def score_from_response(response)
      answer_keys = response.answers.keys
      score_key = if boolify(interpolated['guess_mode'])
                    answer_keys.find { |k| /opinionscale/.match?(k) }
                  else
                    interpolated['score_question_ids'].split(',').find { |id| answer_keys.include?(id) }
                  end

      response.answers[score_key] if score_key.present?
    end

    def comment_from_response(response)
      answer_keys = response.answers.keys
      comment_key = if boolify(interpolated['guess_mode'])
                      answer_keys.find { |k| /textarea/.match?(k) }
                    else
                      interpolated['comment_question_ids'].split(',').find { |id| answer_keys.include?(id) }
                    end

      response.answers[comment_key] if comment_key.present?
    end

    def params
      {
        "order_by[]" => 'date_submit,desc',
        'limit' => interpolated['limit'],
        'offset' => interpolated['offset']
      }
    end

    def typeform
      @typeform ||= Typeform::Form.new(api_key: interpolated['api_key'], form_id: interpolated['form_id'])
    end
  end
end
