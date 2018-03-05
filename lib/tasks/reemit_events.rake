# frozen_string_literal: true

namespace :agent do
  desc 'Re-emit all events for an Agent given an AGENT_ID.'
  task reemit_all_events: :environment do
    raise 'Please specify AGENT_ID' if ENV['AGENT_ID'].blank?

    agent = Agent.find ENV['AGENT_ID']

    puts "Searching events"
    events_ids = agent.events.map(&:id)

    puts "Re-emiting #{events_ids.count} #{'event'.pluralize(events_ids.count)} for '#{agent.name}' agent"
    Event.find(events_ids).each(&:reemit!)

    puts 'Done!'
  end
end
