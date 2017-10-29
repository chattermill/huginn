class TrustPilotParser
  attr_reader :reviews

  def initialize(data)
    @reviews = data['reviews'] || []
  end

  def parse_reviews
    reviews.map do |review|
      ReviewParser.new(review).parse
    end
  end

  class ReviewParser
    ATTRIBUTES = %w[id stars text title language created_at updated_at company_reply
                    is_verified number_of_likes status report_data compliance_labels
                    consumer_name consumer_location].freeze
    attr_reader :data

    def initialize(data)
      @data = OpenStruct.new(data)
    end

    def parse
      ATTRIBUTES.inject({}) { |acc, key| acc.merge(key => extract_data(key)) }
    end

    private

    def extract_data(key)
      attr_name = key.camelize(:lower)
      if data.respond_to?(attr_name)
        data.send(attr_name)
      else
        send(key)
      end
    end

    def consumer_name
      data.dig('consumer', 'displayName')
    end

    def consumer_location
      data.dig('consumer', 'displayLocation')
    end
  end
end
