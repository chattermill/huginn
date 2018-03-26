module Agents
  class AppfiguresReviewsAgent < Agent
    include FormConfigurable
    include WebRequestConcern
    include DeduplicationConcern

    APPFIGURES_URL_BASE = "https://api.appfigures.com/v2/reviews".freeze
    UNIQUENESS_LOOK_BACK = 200
    UNIQUENESS_FACTOR = 3

    description <<-MD
      The AppFigures Agent pulls reviews via [AppFigures API](http://docs.appfigures.com/api/reference/v2/reviews) either for all apps on a given account or
      a reviews for predefined products using AppFigures Public Data API if `products` attribute is defined.

      THe Public Data API uses paid credits and should thus only be used when other options are not available. To get the product ids you need to run the following query: `api.appfigures.com/v2/products/search/@name=app_name`.
      Then list products in the `products` option with a comma.

      The `filters` option is set up to fetch 500 reviews by default and convert them to English automatically. You can find the full list of available params [here](http://docs.appfigures.com/api/reference/v2/reviews).

      `basic_auth` option is supposed to have your AppFigures Login and Password with a colon in between: `login:password`. You should not have actual credentials here, instead save on the Credentials tab as explained [here]()

      `client_key` option has your AppFigures API Client Key, get one [here](https://appfigures.com/developers/keys)
    MD

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule "every_5h"

    form_configurable :filter
    form_configurable :client_key
    form_configurable :basic_auth
    form_configurable :products
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'filter' => 'lang=en&count=5',
        'client_key' => '{% credential AppFiguresClientKey %}',
        'basic_auth' => '{% credential AppFiguresUsername %}:{% credential AppFiguresPassword %}',
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change'
      }
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def validate_options
      %w[client_key basic_auth expected_update_period_in_days].each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end

      if options['mode'].present?
        errors.add(:base, "mode must be set to on_change, all or merge") unless %w[on_change all merge].include?(options['mode'])
      end

      if options['expected_update_period_in_days'].present?
        errors.add(:base, "Invalid expected_update_period_in_days format") unless options['expected_update_period_in_days'].to_i.positive?
      end

      if options['uniqueness_look_back'].present?
        errors.add(:base, "Invalid uniqueness_look_back format") unless (options['uniqueness_look_back']).to_i.positive?
      end

      validate_web_request_options!
    end

    def check
      log "Fetched #{reviews&.size} reviews"
      if reviews.any?
        old_events = previous_payloads(reviews.size * UNIQUENESS_FACTOR, UNIQUENESS_LOOK_BACK)
        reviews.each do |response|
          create_event_from_review(response, old_events)
        end
      end
    end

    private

    def create_event_from_review(response, old_events)
      return unless is_a_valid_product?(response)

      payload = transform_appfigures_responses(response)
      if store_payload?(old_events, payload)
        log "Storing new result for '#{name}': #{payload.inspect}"
        create_event payload: payload
      end
    end

    def is_a_valid_product?(response)
      options['products'].split(',').include?(response['product_id'].to_s)
    end

    def transform_appfigures_responses(response)
      {
        title: response['title'],
        comment: response['review'],
        appfigures_id: response['id'],
        score: response['stars'],
        stream: response['store'],
        created_at: response['date'],
        iso: response['iso'],
        author: response['author'],
        version: response['version'],
        app: response['product_name'],
        product_id: response['product_id'],
        vendor_id: response['vendor_id']
      }
    end

    def reviews
      @reviews ||= fetch_resource["reviews"] || {}
    end

    def fetch_resource
      return unless request_url.present?

      log "Fetching reviews for products: #{options['products']}"
      response = faraday.get(request_url)
      unless response.success?
        log response.body.presence || "Failed response: #{response.status} status"
        return {}
      end
      JSON.parse(response.body)
    end

    def request_url
      return unless params.present?
      "#{APPFIGURES_URL_BASE}?#{params}"
    end

    def params
      return unless options['products'].present?

      query_string = ["products=#{options['products']}"]
      query_string << options['filter'] if options['filter'].present?
      query_string.join('&')
    end

    def headers(_ = {})
      { "X-Client-Key" => interpolated['client_key'] }
    end
  end
end
