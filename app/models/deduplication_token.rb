class DeduplicationToken < ActiveRecord::Base
  belongs_to :agent
  belongs_to :event

  validates_presence_of :token, :agent, :event

  scope :expired,  -> { where("created_at < ?", 3.months.ago) }

  def self.cleanup_expired!
    DeduplicationToken.expired.destroy_all
  end
end
