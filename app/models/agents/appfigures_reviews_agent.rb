module Agents
  class AppfiguresReviewsAgent < WebsiteAgent
    include FormConfigurable

    EXTRACT = {
      'title' => {
        'path' => 'reviews[*].title'
      },
      'comment' => {
        'path' => 'reviews[*].review'
      },
      'appfigures_id' => {
        'path' => 'reviews[*].id'
      },
      'score' => {
        'path' => 'reviews[*].stars'
      },
      'stream' => {
        'path' => 'reviews[*].store'
      },
      'created_at' => {
        'path' => 'reviews[*].date'
      },
      'iso' => {
        'path' => 'reviews[*].iso'
      },
      'author' => {
        'path' => 'reviews[*].author'
      }
    }.freeze

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule "every_5h"

    before_validation :build_default_options

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

    private

    def build_default_options
      options['url'] = "https://api.appfigures.com/v2/reviews"
      options['url'] << "?#{options['filter']}" if options['filter'].present?
      options['url'] << "&#{options['products']}" if options['products'].present?
      options['headers'] = auth_header(
        options['client_key']
      )
      options['type'] = 'json'
      options['extract'] = EXTRACT
    end

    def auth_header(client_key)
      {
        'X-Client-Key' => client_key
      }
    end
  end
end
