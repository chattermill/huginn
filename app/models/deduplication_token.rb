class DeduplicationToken < ActiveRecord::Base
  belongs_to :agent

  validates_presence_of :token, :agent
end
