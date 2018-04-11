# frozen_string_literal: true

require 'chronic'

namespace :agent do
  desc 'Re-emit all events for an Agent given an AGENT_ID. You can use FROM vars to indicate from date, e.g. FROM="2_hours_ago"'
  task reemit_all_events: :environment do
    raise 'Please specify AGENT_ID' if ENV['AGENT_ID'].blank?

    if ENV['FROM'].present?
      Time.zone = "UTC"
      Chronic.time_class = Time.zone

      from = Chronic.parse(ENV['FROM'].tr('_', ' '))
      raise 'Invalid FROM param' if from.nil?
    end

    agent = Agent.find ENV['AGENT_ID']

    puts "Searching events"
    events_ids = agent.events
    events_ids = events_ids.where(created_at: (from..Time.now)) if from

    puts "Re-emiting #{events_ids.count} #{'event'.pluralize(events_ids.count)} for '#{agent.name}' agent"
    Event.find(events_ids.map(&:id)).each(&:reemit!)

    puts 'Done!'
  end
end
