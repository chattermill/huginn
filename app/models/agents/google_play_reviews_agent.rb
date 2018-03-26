require 'google/apis/androidpublisher_v2'

module Agents
  class GooglePlayReviewsAgent < Agent
    include FormConfigurable
    include DeduplicationConcern

    UNIQUENESS_LOOK_BACK = 500
    UNIQUENESS_FACTOR = 5
    AUTH_SCOPE = 'https://www.googleapis.com/auth/androidpublisher'.freeze

    gem_dependency_check { defined?(Google::Apis::AndroidpublisherV2) }

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule 'every_1d'

    description do
      <<-MD
        Google Play Reviews Agent fetches reviews from the Google Play Console given client's JSON file for authentication and package name.

        Please note that only reviews from last week will be returned, read about it [here](https://developers.google.com/android-publisher/api-ref/reviews/list).

        In the `on_change` mode, change is detected based on the resulted event payload after applying this option.
        If you want to add some keys to each event but ignore any change in them, set `mode` to `all` and put a DeDuplicationAgent downstream.
        If you specify `merge` for the `mode` option, Huginn will retain the old payload and update it with new values.

        This agent uses Google Service Accounts authentication, you can read more about it [here](https://developers.google.com/identity/protocols/OAuth2ServiceAccount)

        How to Setup a service account:

        1. Visit [the google api console](https://code.google.com/apis/console/b/0/)
        2. New project -> Huginn
        3. APIs & Auth -> Enable google calendar
        4. Credentials -> Create new Client ID -> Service Account
        5. Download the JSON keyfile and save it, then open that file and copy the content.

        The JSON keyfile should look something like:
        <pre><code>{
          "type": "service_account",
          "project_id": project-123123",
          "private_key_id": "1234567890123456789012345678901234567890",
          "private_key": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n",
          "client_email": "project@project-123123.iam.gserviceaccount.com",
          "client_id": "123123...123123",
          "auth_uri": "https://accounts.google.com/o/oauth2/auth",
          "token_uri": "https://accounts.google.com/o/oauth2/token",
          "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
          "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/project%project-123123.iam.gserviceaccount.com"
        }</code></pre>

        Options:

          * `service_account_json` - Google Service authentication key. Copy and paste file content in JSON format.
          * `package_name` - Unique identifier for the Android app for which we want reviews.
          * `mode` - Select the operation mode (`all`, `on_change`, `merge`).
          * `max_results` - Limit the number of returned reviews (e.g. `1`, `10`).
          * `translation_language` - Translate review comments to specified language (e.g. `es`, `fr`). Original comment will be available on `original_text` field.
          * `expected_receive_period_in_days` - Specify the period in days used to calculate if the agent is working.
      MD
    end

    event_description <<-MD
      Events look like this:

      {
        "author_name": "Test User",
        "review_id": "gpAeVeryLArgRIDxxxxxxxxxx",
        "comment": "\tSo much better. Much more intuitive.",
        "original_comment": null,
        "score": 4,
        "language": "en_GB",
        "updated_at": "2017-09-19 23:00:59 UTC",
        "comments_raw_data": [
          {
            "user_comment": {
              "android_os_version": 24,
              "app_version_code": 108060046,
              "app_version_name": "1.8.6",
              "device": "hero2lte",
              "device_metadata": {
                "cpu_make": "Samsung",
                "cpu_model": "Exynos 8890",
                "device_class": "phone",
                "gl_es_version": 196609,
                "manufacturer": "Samsung",
                "native_platform": "armeabi-v7a,armeabi,arm64-v8a",
                "product_name": "hero2lte (Galaxy S7 Edge)",
                "ram_mb": 4096,
                "screen_density_dpi": 640,
                "screen_height_px": 2560,
                "screen_width_px": 1440
              },
              "last_modified": {
                "nanos": 244000000,
                "seconds": 1505862059
              },
              "reviewer_language": "en_GB",
              "star_rating": 4,
              "text": "\tSo much better. Much more intuitive.",
              "thumbs_down_count": 0,
              "thumbs_up_count": 0
            }
          }
        ]
      }
    MD

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    form_configurable :service_account_json, type: :json, ace: { mode: 'json' }
    form_configurable :package_name
    form_configurable :mode, type: :array, values: %w(all on_change merge)
    form_configurable :max_results
    form_configurable :translation_language
    form_configurable :expected_update_period_in_days

    def default_options
      {
        'service_account_json' => '',
        'package_name' => 'uk.co.my.app',
        'translation_language' => 'en',
        'expected_update_period_in_days' => '1',
        'mode' => 'on_change'
      }
    end

    def validate_options
      super

      validate_json_option('service_account_json')

      %w(package_name expected_update_period_in_days).each do |key|
        errors.add(:base, "The '#{key}' option is required.") if options[key].blank?
      end
    end

    def check
      return unless retrieve_reviews.any?

      old_events = previous_payloads(retrieve_reviews.size * UNIQUENESS_FACTOR, UNIQUENESS_LOOK_BACK)
      retrieve_reviews.each do |review|
        payload = prepare_event(review)
        if store_payload?(old_events, payload)
          log "Storing new result for '#{name}': #{review.inspect}"
          create_event payload: payload
        end
      end
    end

    private

    def validate_json_option(key)
      JSON.parse(options[key])
    rescue
      errors.add(:base, "The '#{key}' option is an invalid JSON.")
    end

    def prepare_event(review)
      comment = review.comments.first.user_comment
      {
        author_name: review.author_name,
        review_id: review.review_id,
        comment: comment.text,
        original_comment: comment&.original_text,
        score: comment.star_rating,
        language: comment.reviewer_language,
        updated_at: Time.at(comment.last_modified.seconds).utc.as_json,
        comments_raw_data: review.comments.map(&:to_h)
      }
    end

    def retrieve_reviews
      params = {
        max_results: interpolated['max_results'].presence,
        translation_language: interpolated['translation_language'].presence
      }

      @retrieve_reviews ||= google_play_api.list_reviews(interpolated['package_name'], params).reviews
    end

    def google_play_api
      api = Google::Apis::AndroidpublisherV2::AndroidPublisherService.new
      api.authorization = authorizer

      api
    end

    def authorizer
      auth = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: service_account_json_io, scope: AUTH_SCOPE
      )

      auth.fetch_access_token!
      auth
    end

    def service_account_json_io
      StringIO.new(interpolated['service_account_json'])
    end
  end
end
