# frozen_string_literal: true

require 'chronic'

namespace :chattermill do
  desc 'Re-emit source events for ChattermillResponseAgent. Use FROM and TO vars to indicate time range, e.g. FROM="2_hours_ago" TO="10_minutes_ago"'
  task reemit_failed_events: :environment do
    raise 'Please specify FROM and TO params.' if ENV['FROM'].blank? || ENV['TO'].blank?

    Time.zone = "UTC"
    Chronic.time_class = Time.zone

    from = Chronic.parse(ENV['FROM'].tr('_', ' '))
    raise 'Invalid FROM param' if from.nil?

    to = Chronic.parse(ENV['TO'].tr('_', ' '))
    raise 'Invalid TO param' if to.nil?

    puts "Searching failed events between #{from} and #{to}"

    statuses = ['%502 Bad Gateway%', '%504 Gateway Time-out%', '%something went wrong (500)%']

    statuses.each do |status|
      events = Event.joins(:agent)
                    .where(created_at: (from..to))
                    .where("payload LIKE ?", status)
                    .where('agents.type': 'Agents::ChattermillResponseAgent')

      source_events = events.map { |e| e.payload['source_event'] }.compact

      if source_events.empty?
        puts "No events to re-emit for '#{status}' errors"
      else
        puts "Re-emiting #{source_events.count} #{'event'.pluralize(source_events.count)} for '#{status}' errors"
        Event.find(source_events).each(&:reemit!)
      end
    end

    puts 'Done!'
  end
end
