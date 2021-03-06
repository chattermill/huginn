module Agents
  class UsabillaAgent < Agent
    include FormConfigurable
    include DeduplicationConcern

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 5

    gem_dependency_check { defined?(UsabillaApi) }

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_1d'

    description do
      <<-MD
        Usabilla Agent fetches responses from the Usabilla API given client's access details and a list of surveys.

        In Usabilla terminlogy, there are four types of feedback:
        - Buttons
        - Campaigns
        - Emails
        - Apps

        This agent currently only implements buttons, emails and apps. We might add campaigns in the future.

        For each data type you need to switch on the option to fetch this data and then provide a list of ids. For example,
        to enable buttons set `retrieve_buttons` option to `true` and provide a list of ids to `buttons_to_retrieve` option.

        The `*` list should in theory fetch all ids on the account but does not work correctly.

        In the `on_change` mode, change is detected based on the resulted event payload after applying this option.
        If you want to add some keys to each event but ignore any change in them, set `mode` to `all` and put a DeDuplicationAgent downstream.
        If you specify `merge` for the `mode` option, Huginn will retain the old payload and update it with new values.

        Options:

          * `access_key` - Usabilla Access Key.
          * `secret_key` - Usabilla Secret Key.
          * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
          * `retrieve_buttons` - If `true`, the agent wil retrieve feedback for buttons from the `buttons_to_retrieve` list
          * `retrieve_emails` - If `true`, the agent wil retrieve feedback for emails from the `emails_to_retrieve` list
          * `retrieve_apps` - If `true`, the agent wil retrieve feedback for apps from the `apps_to_retrieve` list
          * `retireve_campaigns` - If `true` the agent will retrieve for campaigns from the `campaigns_to_retrieve` list
          * `days_ago` - How many days to look back, you won't be able to go too many due to API only fetching up to 100 items for each call
          * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
      MD
    end

    event_description <<-MD
      Events look like this (currently only buttons are configured fully):
        {
          "comment": "Very quick service very happy delivery service and delicious food... highly recommended thanks again x",
          "score": 5,
          "location": "Birmingham, United Kingdom",
          "id": "5964fcb0f3f5457c8b20841b",
          "custom": {
          },
          "public_url": "https://www.usabilla.com/feedback/item/4ae8552ead55367026bf33cf7c9f67553c23d6ba",
          "button_id": "31a8642b92fc",
          "created_at": "2017-07-11T16:28:41.929Z",
          "email": ""
        }
    MD

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    form_configurable :access_key
    form_configurable :secret_key
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :retrieve_buttons, type: :array, values: %w(true false)
    form_configurable :buttons_to_retrieve
    form_configurable :retrieve_apps, type: :array, values: %w(true false)
    form_configurable :apps_to_retrieve
    form_configurable :retrieve_emails, type: :array, values: %w(true false)
    form_configurable :emails_to_retrieve
    form_configurable :retrieve_campaigns, type: :array, values: %w(true false)
    form_configurable :campaigns_to_retrieve
    form_configurable :days_ago
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'access_key' => '{% credential UsabillaAccessKey %}',
        'secret_key' => '{% credential UsabillaSecretKey %}',
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change',
        'retrieve_buttons' => 'false',
        'retrieve_apps' => 'false',
        'retrieve_emails' => 'false',
        'retrieve_campaigns' => 'false',
        'buttons_to_retrieve' => '*',
        'emails_to_retrieve' => '*',
        'apps_to_retrieve' => '*',
        'campaigns_to_retrieve' => '*',
        'days_ago' => '1'
      }
    end

    def validate_options
      super

      %w(access_key secret_key).each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      if boolify(options['retrieve_buttons']).nil?
        errors.add(:base, 'The retrieve_buttons option must be true or false')
      end

      if boolify(options['retrieve_apps']).nil?
        errors.add(:base, 'The retrieve_apps option must be true or false')
      end

      if boolify(options['retrieve_emails']).nil?
        errors.add(:base, 'The retrieve_emails option must be true or false')
      end

      if boolify(options['retrieve_campaigns']).nil?
        errors.add(:base, 'The retrieve_campaigns option must be true or false')
      end

      if options['expected_update_period_in_days'].present?
        errors.add(:base, "Invalid expected_update_period_in_days format") unless options['expected_update_period_in_days'].to_i.positive?
      end

      if options['uniqueness_look_back'].present?
        errors.add(:base, "Invalid uniqueness_look_back format") unless (options['uniqueness_look_back']).to_i.positive?
      end

    end

    def check
      new_events = retrieve_events
      if new_events.any?
        old_events = previous_payloads(new_events.size)
        new_events.each do |e|
          payload = usabilla_response_to_event(e)
          if store_payload?(old_events, payload)
            log "Storing new result for '#{name}': #{payload.inspect}"
            create_event payload: payload
          end
        end
      end
    end

    private

    def retrieve_events
      events = []
      events += retrieve_buttons if retrieve_buttons?
      events += retrieve_apps if retrieve_apps?
      events += retrieve_emails if retrieve_emails?
      events += retrieve_campaigns if retrieve_campaigns?
      events
    end

    def retrieve_buttons?
      boolify(interpolated['retrieve_buttons'])
    end

    def retrieve_apps?
      boolify(interpolated['retrieve_apps'])
    end

    def retrieve_emails?
      boolify(interpolated['retrieve_emails'])
    end

    def retrieve_campaigns?
      boolify(interpolated['retrieve_campaigns'])
    end

    def retrieve_buttons
      ids = interpolated['buttons_to_retrieve'].split(',')
      ids.map do |id|
        usabilla_api
          .websites_feedback
          .retrieve(
            id: id,
            access_key: interpolated['access_key'],
            secret_key: interpolated['secret_key'],
            days_ago: interpolated['days_ago']
          ).items
      end.flatten
    end

    def retrieve_apps
      ids = interpolated['apps_to_retrieve'].split(',')
      ids.map do |id|
        usabilla_api
          .apps_feedback
          .retrieve(
            id: id,
            access_key: interpolated['access_key'],
            secret_key: interpolated['secret_key'],
            days_ago: interpolated['days_ago']
          ).items
      end.flatten
    end

    def retrieve_emails
      ids = interpolated['emails_to_retrieve'].split(',')
      ids.map do |id|
        usabilla_api
          .email_button
          .retrieve(
            id: id,
            access_key: interpolated['access_key'],
            secret_key: interpolated['secret_key'],
            days_ago: interpolated['days_ago']
          ).items
      end.flatten
    end

    def retrieve_campaigns
      ids = interpolated['campaigns_to_retrieve'].split(',')
      ids.map do |id|
        usabilla_api
          .websites_campaign_results
          .retrieve(
            id: id,
            access_key: interpolated['access_key'],
            secret_key: interpolated['secret_key'],
            days_ago: interpolated['days_ago']
          ).items
      end.flatten
    end

    def usabilla_response_to_event(r)
      {
        comment: extract_comment(r),
        score: extract_score(r),
        location: r.location,
        id: r.id,
        custom: r.custom,
        public_url: extract_if_present(:public_url, r),
        button_id: extract_if_present(:button_id, r),
        created_at: r.date,
        email: extract_if_present(:email, r),
        raw_data: r.raw_data
      }
    end

    def extract_comment(response)
      return response.comment if response.respond_to?(:comment)

      if response.respond_to?(:data) && response.data.is_a?(Hash)
        response.data.find { |k, v| k.to_s.start_with?('comment') && v.present? }&.last
      end
    end

    def extract_score(response)
      return response.rating if response.respond_to?(:rating)
      response.data[:mood] || response.data[:nps] if response.respond_to?(:data) && response.data.is_a?(Hash)
    end

    def extract_if_present(attr_name, response)
      response.send(attr_name) if response.respond_to?(attr_name)
    end

    def usabilla_api
      UsabillaApi
    end
  end
end
