# frozen_string_literal: true
require 'chronic'

module Agents
  class TypeformResponseAgent < Agent
    include FormConfigurable

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 1

    gem_dependency_check { defined?(Typeform) }

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_5h'

    before_validation :parse_json_options

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
        * `limit` - Number of responses to fetch per run, better to set to a low number and have the agent run more often.
        * `since` - Specify date and time, to limit request to responses submitted since the specified date and time, e.g. `8 hours ago`, `may 27th` [more valid formats](https://github.com/mojombo/chronic).
        * `until` - Specify date and time, to limit request to responses submitted until the specified date and time, e.g. `1979-05-27 05:00:00`, `January 5 at 7pm` [more valid formats](https://github.com/mojombo/chronic).
        * `mapping_object` - Specify the mapping definition object where any hidden_variables can be mapped with a single value.
        * `bucketing_object` - Specify the bucketing definition object where any hidden_variables can be broken into a specific bucket.
        * `uniqueness_look_back` - Set the limit the number of events checked for uniqueness (typically for performance).  This defaults to the larger of #{UNIQUENESS_LOOK_BACK} or #{UNIQUENESS_FACTOR}x the number of detected received results.

        If you specify `mapping_object` you must set up something like this:


            "city_id": {
              "1": "London",
              "2": "New York"
            },
            "country_id": {
              "1": "UK",
              "2": "US"
            }

        If you specify `bucketing_object` you must set up something like this:

            "tc": {
              "1": "First Trip",
              "2-10": "2 - 10",
              "11-20": "11 - 20",
              "21-50": "21 - 50",
              "51-100": "51 - 100",
              "100+": "101 and more"
            }
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
          },
          "mapped_variables": {
            "city_id": "London"
            "country_id": "UK",
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
    form_configurable :mapping_object, type: :json, ace: { mode: 'json' }
    form_configurable :bucketing_object, type: :json, ace: { mode: 'json' }
    form_configurable :mode, type: :array, values: %w[all on_change merge]
    form_configurable :uniqueness_look_back
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'access_token' => '{% credential TypeformAccessToken %}',
        'guess_mode' => true,
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change',
        'limit' => 20,
        'mapping_object' => '{}',
        'bucketing_object' => '{}'
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

      if options['expected_update_period_in_days'].present?
        errors.add(:base, "Invalid expected_update_period_in_days format") unless options['expected_update_period_in_days'].to_i.positive?
      end

      if options['uniqueness_look_back'].present?
        errors.add(:base, "Invalid uniqueness_look_back format") unless (options['uniqueness_look_back']).to_i.positive?
      end

    end

    def check
      avoid_concurrent_running do
        if typeform_events.any?
          old_events = previous_payloads(typeform_events.size)
          typeform_events.each do |e|
            if store_payload!(old_events, e)
              log "Storing new result for '#{name}': #{e.inspect}"
              create_event payload: e
            end
          end
        end
      end
    end

    private

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

    def sorted_answers(answers)
      answers.sort_by { |el| el['field']['id'] }
    end

    def typeform_events
      typeform.complete_entries(params).items.map { |r| transform_typeform_responses(r) }
    end

    def transform_typeform_responses(response)
      answers = sorted_answers(response.answers || [])
      {
        score: score_from_response(answers),
        comment: comment_from_response(answers),
        created_at: response.submitted_at,
        id: response.token,
        answers: answers,
        formatted_answers: transform_answers(answers),
        metadata: response.metadata,
        hidden_variables: response.hidden,
        mapped_variables: mapping_from_response(response)
      }
    end

    def score_from_response(answers)
      answer = if boolify(interpolated['guess_mode'])
                 answers.find {|h| h.field.type == "opinion_scale" }
               else
                 answer_for(answers, interpolated['score_question_ids'])
               end

      answer.number if answer.present?
    end

    def comment_from_response(answers)
      answer = if boolify(interpolated['guess_mode'])
                 answers.find { |h| h["field"]["type"] == "long_text" }
               else
                 answer_for(answers, interpolated['comment_question_ids'])
               end

      answer.text if answer.present?
    end

    def answer_for(answers, option_ids)
      answers_ids = answers.map {|a| a.field.id }
      key = option_ids.split(',').find { |id| answers_ids.include?(id) }
      answers.find {|h| h.field.id == key }
    end

    def transform_answers(answers)
      answers.each_with_object({}) do |a, hash|
        hash["#{a.field.type}_#{a.field.id}"] = a.send(a.type)
      end
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

    def parse_json_options
      parse_json_option('mapping_object')
      parse_json_option('bucketing_object')
    end

    def parse_json_option(key)
      options[key] = JSON.parse(options[key]) unless options[key].is_a?(Hash)
    rescue
      errors.add(:base, "The '#{key}' option is an invalid JSON.")
    end

    def mapping_from_response(response)
      mapped_variables = {}
      mapped_variables.merge!(single_values_mapping(response))
      mapped_variables.merge!(value_ranges_mapping(response))
    end

    def single_values_mapping(response)
      hash = {}
      mapping = options["mapping_object"]
      if mapping.present?
        response.hidden.each do |k, v|
          hash[k] = mapping[k].fetch(v, v) if mapping.key?(k)
        end
      end
      hash
    end

    def value_ranges_mapping(response)
      hash = {}
      mapping = options["bucketing_object"]
      if mapping.present?
        response.hidden.each do |k, v|
          hash[k] = extract_bucket(mapping[k], v) || v if mapping.key?(k)
        end
      end
      hash
    end

    def extract_bucket(hash, value)
      value = value.to_i
      bucket = nil
      hash.each do |k, v|
        range = k.split("-")
        min = range.first
        max = range.last
        if /\+/ =~ max && value >= max.tr("+", "").to_i
          bucket = v
          break
        elsif (min.to_i..max.to_i).cover?(value)
          bucket = v
          break
        end
      end
      bucket
    end

    def agent_in_process?
      boolify(memory['in_process'])
    end

    def process_agent!
      memory['in_process'] = true
      save!
    end

    def avoid_concurrent_running
      raise 'Mising block' unless block_given?
      unless agent_in_process?
        process_agent!
        yield
        memory['in_process'] = false
      end
    rescue
      memory['in_process'] = false
      save!
      raise
    end
  end
end
