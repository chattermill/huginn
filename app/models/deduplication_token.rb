class DeduplicationToken < ActiveRecord::Base
  belongs_to :agent
  belongs_to :event

  validates_presence_of :token, :agent, :event
end
