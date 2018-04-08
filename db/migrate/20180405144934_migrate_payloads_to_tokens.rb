class MigratePayloadsToTokens < ActiveRecord::Migration[5.1]
  def up

    agents = [
      "Agents::TypeformAgent",
      "Agents::WebsiteAgent",
      "Agents::AppfiguresReviewsAgent",
      "Agents::ZendeskSatisfactionRatingsAgent",
      "Agents::TypeformResponseAgent",
      "Agents::SurveyMonkeyAgent",
      "Agents::GooglePlayReviewsAgent",
      "Agents::UsabillaAgent",
      "Agents::DelightedAgent" ].freeze

    agents.each do |a|

      klass = a.constantize
      klass.all.each do |agent|
        events = agent.events.where("created_at > ?", 1.month.ago).limit(uniqueness_look_back(agent))
        events.find_in_batches do |group|
          group.each do |e|
            e.create_token!(agent: agent, token: Digest::SHA256.hexdigest(e.payload.to_json))
          end
        end
      end
    end
  end

  def down
    DeduplicationToken.destroy_all
  end

  def uniqueness_look_back(agent)
    return agent.interpolated['uniqueness_look_back'].to_i if agent.interpolated['uniqueness_look_back'].present?
    agent.class.const_get(:UNIQUENESS_LOOK_BACK)
  end
end
