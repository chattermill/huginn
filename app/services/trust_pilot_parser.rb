class TrustPilotParser
  attr_reader :reviews

  def initialize(data)
    @reviews = data['reviews'] || []
  end

  def parse_reviews
    reviews.map do |data|
      Review.new(data).parse
    end
  end

  class Review < OpenStruct
    ATTRIBUTES = %w[response_id score comment title language created_at email user_reference_id].freeze

    def initialize(hash = nil)
      hash.deep_transform_keys!(&:underscore)
      super
    end

    def response_id
      self['id']
    end

    def score
      self['stars']
    end

    def comment
      self['text']
    end

    def email
      self['referral_email']
    end

    def user_reference_id
      self['reference_id']
    end

    def parse
      ATTRIBUTES.inject({}) { |acc, key| acc.merge(key => send(key)) }
    end
  end
end
