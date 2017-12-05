# frozen_string_literal: true

namespace :sidekiq do
  desc 'Send sidekiq queue metrics to Cloudwatch'
  task send_queue_metrics: :environment do
    puts "Getting queues data"
    queues = Sidekiq::Queue.all.each_with_object({}) do |queue, hash|
      hash[queue.name] = {
        size: { value: queue.size, unit: 'Count' },
        latency: { value: queue.latency.to_i, unit: 'Seconds' }
      }
    end

    puts 'Sending metrics to CloudWatch'
    CloudwatchMetricCreator.new("Huginn/Sidekiq", "Queue Name", queues).create!
    puts 'Done!'
  end
end
