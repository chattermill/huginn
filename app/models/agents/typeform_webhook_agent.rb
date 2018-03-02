module Agents
  class TypeformWebhookAgent < WebhookAgent
    include FormConfigurable

    TYPEFORM_URL_BASE = 'https://api.typeform.com'.freeze

    cannot_be_scheduled!
    cannot_receive_events!

    before_validation :parse_json_options
    after_save :set_typeform_webhook

    description do
      <<-MD
        The Typeform Webhook Agent will create events by receiving webhooks from Typeform.
        In order to create events with this agent, make a POST request to:

        ```
           https://#{ENV['DOMAIN']}/users/#{user.id}/web_requests/#{id || ':id'}/#{options['secret'] || ':secret'}
        ```

        #{'The placeholder symbols above will be replaced by their values once the agent is saved.' unless id}

        Options:

          * `access_token` - Typeform API Key.
          * `form_id` - Typeform Form ID.
          * `guess_mode` - Let the agent try to figure out the score question and the comment question automatically using the first `opinionscale` question and the first `textarea` question
          * `score_question_ids` - Hard-code the comma separated list of ids of the score questions (agent will pick the first one present) if `guess_mode` is off. Only Id, example: `"58048493,58048049"`
          * `comment_question_ids` - Hard-code he comma separated list of ids of the comment questions (agent will pick the first one present) if `guess_mode` is off. Only Id, example: `"5804976588,58049969,58049765"`
          * `mapping_object` - Specify the mapping definition object where any hidden_variables can be mapped with a single value.
          * `bucketing_object` - Specify the bucketing definition object where any hidden_variables can be broken into a specific bucket.
          * `expected_receive_period_in_days` - How often you expect to receive events this way. Used to determine if the agent is working.
      MD
    end


    event_description do
      <<-MD
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
    end


    def default_options
      {
        'access_token' => '{% credential TypeformAccessToken %}',
        'guess_mode' => true,
        'mapping_object' => '{}',
        'bucketing_object' => '{}',
        "secret" => SecureRandom.hex,
        "expected_receive_period_in_days" => 1,
        "payload_path" => "."
      }
    end

    form_configurable :access_token
    form_configurable :form_id
    form_configurable :guess_mode, type: :boolean
    form_configurable :score_question_ids
    form_configurable :comment_question_ids
    form_configurable :mapping_object, type: :json, ace: { mode: 'json' }
    form_configurable :bucketing_object, type: :json, ace: { mode: 'json' }
    form_configurable :expected_receive_period_in_days
    form_configurable :secret
    form_configurable :payload_path

    def validate_options
      %w[access_token form_id].each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      super
    end

    def receive_web_request(params, method, format)
      # check the secret
      secret = params.delete('secret')
      return ["Not Authorized", 401] unless secret == interpolated['secret']

      # check the verbs
      verbs = (interpolated['verbs'] || 'post').split(/,/).map { |x| x.strip.downcase }.select { |x| x.present? }
      return ["Please use #{verbs.join('/').upcase} requests only", 401] unless verbs.include?(method)

      # check the code
      code = (interpolated['code'].presence || 201).to_i

      [payload_for(params)].flatten.each do |payload|
        event_payload = transform_typeform_response(payload)
        create_event(payload: event_payload) if event_payload
      end

      if interpolated['response_headers'].presence
        [interpolated(params)['response'] || 'Event Created', code, "text/plain", interpolated['response_headers'].presence]
      else
        [interpolated(params)['response'] || 'Event Created', code]
      end
    end

    private

    def transform_typeform_response(payload)
      response = payload['form_response']
      return if response.blank?

      answers = sorted_answers(response['answers'])
      {
        score: score_from_response(answers),
        comment: comment_from_response(answers),
        created_at: response['submitted_at'],
        id: response['token'],
        answers: answers,
        formatted_answers: transform_answers(answers),
        metadata: response['metadata'],
        hidden_variables: response['hidden'],
        mapped_variables: mapping_from_response(response)
      }
    end

    def sorted_answers(answers)
      (answers || []).sort_by { |el| el['field']['id'] }
    end

    def score_from_response(answers)
      answer = if boolify(interpolated['guess_mode'])
                 answers.find {|h| h['field']['type'] == "opinion_scale" }
               else
                 answer_for(answers, interpolated['score_question_ids'])
               end

      answer['number'] if answer.present?
    end

    def comment_from_response(answers)
      answer = if boolify(interpolated['guess_mode'])
                 answers.find { |h| h["field"]["type"] == "long_text" }
               else
                 answer_for(answers, interpolated['comment_question_ids'])
               end

      answer['text'] if answer.present?
    end

    def answer_for(answers, option_ids)
      answers_ids = answers.map {|a| a['field']['id'] }
      key = option_ids.split(',').find { |id| answers_ids.include?(id) }
      answers.find {|h| h['field']['id'] == key }
    end

    def transform_answers(answers)
      answers.each_with_object({}) do |a, hash|
        hash["#{a['field']['type']}_#{a['field']['id']}"] = a.fetch(a['type'])
      end
    end

    def mapping_from_response(response)
      return if response['hidden'].blank?

      mapped_variables = {}
      mapped_variables.merge!(single_values_mapping(response))
      mapped_variables.merge!(value_ranges_mapping(response))
    end

    def single_values_mapping(response)
      hash = {}
      mapping = options["mapping_object"]
      if mapping.present?
        response['hidden'].each do |k, v|
          hash[k] = mapping[k].fetch(v, v) if mapping.key?(k)
        end
      end
      hash
    end

    def value_ranges_mapping(response)
      hash = {}
      mapping = options["bucketing_object"]
      if mapping.present?
        response['hidden'].each do |k, v|
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

    def parse_json_options
      parse_json_option('mapping_object')
      parse_json_option('bucketing_object')
    end

    def parse_json_option(key)
      options[key] = JSON.parse(options[key]) unless options[key].is_a?(Hash)
    rescue
      errors.add(:base, "The '#{key}' option is an invalid JSON.")
    end

    def set_typeform_webhook
      enabled = !self.disabled
      body = {
        "url": "https://#{ENV['DOMAIN']}/users/#{user.id}/web_requests/#{id}/#{options['secret']}",
        "enabled": enabled
      }
      response = faraday.put(webhook_url, body.to_json, headers(auth_header))
      log "Typeform Response: #{response.status}: #{response.body}"
    end

    def webhook_url
      form = interpolated['form_id']
      tag = "agent_#{id}"
      "#{TYPEFORM_URL_BASE}/forms/#{form}/webhooks/#{tag}"
    end

    def auth_header
      {
        'Content-Type' => 'application/json; charset=utf-8',
        'Authorization' =>  "Bearer #{interpolated['access_token']}"
      }
    end

  end
end
