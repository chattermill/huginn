module Agents
  class DelightedAgent < Agent
    include FormConfigurable
    include DeduplicationConcern

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 3

    gem_dependency_check { defined?(Delighted) }

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_5h'

    description <<-MD
      Delighted Agent fetches responses from the Delighted API given client's access details.

      In the `on_change` mode, change is detected based on the resulted event payload after applying this option.
      If you want to add some keys to each event but ignore any change in them, set `mode` to `all` and put a DeDuplicationAgent downstream.
      If you specify `merge` for the `mode` option, Huginn will retain the old payload and update it with new values.

      Options:

        * `api_key` - Delighted API Key.
        * `page` - Response page to fetch
        * `per_page` - Number of responses per page (max is 100)
        * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
        * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
    MD

    event_description <<-MD
      Events look like this:
        {
          "id": 123,
          "score": 9,
          "comment": "Love the concept and the food! Just a little too expensive.",
          "permalink": "https://delighted.com/r/hqt5a8UlaZ1Vie9vsdSCtpo3iJaLrZPX",
          "created_at": 1499888649,
          "updated_at": 1499888686,
          "person_properties": {},
          "notes": [
          ],
          "tags": [
          ],
          "person": "138373225"
      }
    MD

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    form_configurable :api_key
    form_configurable :page
    form_configurable :per_page
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'api_key' => '{% credential DelightedApiKey %}',
        'page' => '1',
        'per_page' => '100',
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change'
      }
    end

    def validate_options
      super

      %w(api_key).each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end
    end

    def check
      if delighted_events.any?
        old_events = previous_payloads(delighted_events.size)
        delighted_events.each do |e|
          if store_payload?(old_events, e)
            log "Storing new result for '#{name}': #{e.inspect}"
            create_event payload: e
          end
        end
      end
    end

    private

    def delighted_events
      @delighted_events ||= list_delighted_responses.map { |r| r.to_h.merge(id: r.id) }
    end

    def list_delighted_responses
      Delighted::SurveyResponse.all(default_query, delighted_client)
    end

    def default_query
      {
        order: 'desc',
        page: page,
        per_page: per_page,
        expand: ['person']
      }
    end

    def page
      interpolated['page']
    end

    def per_page
      interpolated['per_page']
    end

    def delighted_client
      @delighted_client ||= Delighted::Client.new(api_key: interpolated['api_key'])
    end
  end
end
