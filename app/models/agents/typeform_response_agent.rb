# frozen_string_literal: true
require 'chronic'

module Agents
  class TypeformResponseAgent < WebsiteAgent
    include FormConfigurable

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 1

    API_ENDPOINT = "responses"
    DOMAIN = "api.typeform.com/forms"

    EXTRACT = {
      'review' => { 'path' => 'items.[*]' }
    }.freeze

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_5h'

    before_validation :build_default_options

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
        * `score_question_ids` - Hard-code the comma separated list of ids of the score questions (agent will pick the first one present) if `guess_mode` is off. Only Id, example: `"58048493,58048049"`
        * `comment_question_ids` - Hard-code he comma separated list of ids of the comment questions (agent will pick the first one present) if `guess_mode` is off. Only Id, example: `"5804976588,58049969,58049765"`
        * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
        * `page_size` - Number of responses to fetch per run, better to set to a low number and have the agent run more often.
        * `since` - Specify date and time, to limit request to responses submitted since the specified date and time, e.g. `8 hours ago`, `may 27th` [more valid formats](https://github.com/mojombo/chronic).
        * `until` - Specify date and time, to limit request to responses submitted until the specified date and time, e.g. `1979-05-27 05:00:00`, `January 5 at 7pm` [more valid formats](https://github.com/mojombo/chronic).
        * `before` - Limit request to responses submitted before the specified ID.
        * `after` - Limit request to responses submitted after the specified ID.
        * `completed` - true if form was submitted. Otherwise, false.
        * `uniqueness_look_back` - Set the limit the number of events checked for uniqueness (typically for performance).  This defaults to the larger of #{UNIQUENESS_LOOK_BACK} or #{UNIQUENESS_FACTOR} x the number of detected received results.
    MD

    event_description <<-MD
      Events look like this:
        "score": 9,
        "comment": "Love the concept and the food! Just a little too expensive.",
        "id": "62e3caeaca5100adf84f61708ad69960",
        "created_at": "2017-08-12 19:16:02",
        "answers": [
          {
            "field": {
              "id": "58048493",
              "type": "opinion_scale"
            },
            "type": "number",
            "number": 4
          },
          {
            "field": {
              "id": "58049765",
              "type": "dropdown"
            },
            "type": "text",
            "text": "£30,000 - £39,999"
          },
          {
            "field": {
              "id": "58049969",
              "type": "long_text"
            },
            "type": "text",
            "text": "I do like knowing about my financial state and the Clearscore report  makes me feel like I'm doing something right. However I don't think my world would end if I did'nt have Clearscore, but I do look forward to their next update  "
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
          }
        ],
        "formatted_answers": {
          "opinion_scale_58048690": 3,
          "long_text_58049969": "It is really helpful to see your credit score at any time and if it changes then why gas it changed",
          "opinion_scale_58048493": 5,
          "opinion_scale_58048704": 2,
          "dropdown_58049487": "South East",
          "opinion_scale_58048049": 10,
          "opinion_scale_58048684": 3,
          "opinion_scale_58048687": 3,
          "multiple_choice_58049393": {
            "label": "55 to 64"
          },
          "dropdown_58049765": "< £20,000"
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
          "survey_name": "login_monthly",
          "city_id": "458",
          "country_id": "25",
          "tc": "2"
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
    form_configurable :page_size
    form_configurable :since
    form_configurable :until
    form_configurable :before
    form_configurable :after
    form_configurable :sort
    form_configurable :completed, type: :array, values: %w(true false null)
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :uniqueness_look_back
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'access_token' => '{% credential TypeformAccessToken %}',
        'guess_mode' => true,
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change',
        'page_size' => 5,
        'sort' => 'submitted_at,desc',
        'completed' => true
      }
    end

    def validate_options
      super

      %w(access_token form_id).each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end
    end

    private

    def build_default_options
      options['type'] = 'json'
      options['url'] = url

      options['headers'] = {
        'Authorization' => "bearer #{options['access_token']}"
      }
      options['extract'] = EXTRACT
    end

    def url
      "https://#{DOMAIN}/#{options['form_id']}/#{API_ENDPOINT}?#{params.to_query}"
    end

    def previous_payloads(num_events)
      if interpolated['uniqueness_look_back'].present?
        look_back = interpolated['uniqueness_look_back'].to_i
      else
        # Larger of UNIQUENESS_FACTOR * num_events and UNIQUENESS_LOOK_BACK
        look_back = UNIQUENESS_FACTOR * num_events
        look_back = UNIQUENESS_LOOK_BACK if look_back < UNIQUENESS_LOOK_BACK
      end

      events.order('id desc nulls last').limit(look_back) if interpolated['mode'] == 'on_change'
    end

    def store_payload!(old_events, result)
      result_json = transform_typeform_responses(result['review'])

      if found = old_events.find { |event| event.payload.to_json == result_json }
        found.update!(expires_at: new_event_expiration_date)
        false
      else
        true
      end
    end

    def handle_data(body, _url, _existing_payload)
      doc = parse(body)

      output = extract_json(doc)

      num_tuples = output.size or
        raise "At least one non-repeat key is required"

      old_events = previous_payloads num_tuples

      output.each do |extracted|
        result = extracted.except(*output.hidden_keys)

        if store_payload!(old_events, result)
          log "Storing new parsed result for '#{name}': #{result.inspect}"
          create_event payload: transform_typeform_responses(result['review'])
        end
      end
    end

    def extract_json(doc)
      raw_json = super(doc)
    end

    def transform_typeform_responses(response)
      answers = sorted_answers(response['answers'])

      {
        score: score_from_response(answers),
        comment: comment_from_response(answers),
        created_at: response['submitted_at'],
        id: response['token'],
        answers: answers,
        formatted_answers: transform_answers(answers),
        metadata: response['metadata'],
        hidden_variables: response['hidden']
      }
    end

    def sorted_answers(answers)
      answers.sort_by { |el| el.dig('field', 'id') }
    end

    def score_from_response(answers)
      answer = if boolify(interpolated['guess_mode'])
                 answers.find { |h| h.dig('field', 'type') == "opinion_scale" }
               else
                 answer_for(answers, interpolated['score_question_ids'])
               end

      answer.dig('number') if answer.present?
    end

    def comment_from_response(answers)
      answer = if boolify(interpolated['guess_mode'])
                 answers.find { |h| h.dig('field', 'type') == "long_text" }
               else
                 answer_for(answers, interpolated['comment_question_ids'])
               end

      answer.dig('text') if answer.present?
    end

    def answer_for(answers, option_ids)
      answers_ids = answers.map { |a| a.dig('field', 'id') }
      key = option_ids.split(',').find { |id| answers_ids.include?(id) }
      answers.find { |_h| a.dig('field', 'id') == key }
    end

    def transform_answers(answers)
      answers.each_with_object({}) do |a, hash|
        hash["#{a.dig('field', 'type')}_#{a.dig('field', 'id')}"] = a['type']
      end
    end

    def params
      {
        'page_size' => interpolated['page_size'],
        'since' => interpolated['since'],
        'until' => interpolated['until'],
        'before' => interpolated['before'],
        'after' => interpolated['after'],
        'completed' => interpolated['completed'],
        'sort' => interpolated['sort']
      }
    end
  end
end
