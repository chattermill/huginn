# frozen_string_literal: true

namespace :agents do
  desc 'set in_process flag to false for some agents'
  task clean_in_process_memory: :environment do
    agent_classes = %w[AppfiguresReviewsAgent ChattermillResponseAgent DelightedAgent SurveyMonkeyAgent TypeformAgent TypeformResponseAgent UsabillaAgent]

    agent_classes.each do |a|
      puts "Setting #{a} agents"
      klass = "Agents::#{a}".constantize
      klass.find_each do |agent|
        agent.memory['in_process'] = false
        agent.save!
      end
    end
    puts 'Done!'
  end
end
