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

    total_size = queues.values.reduce(0) { |sum, e| sum + e[:size][:value] }
    summary = Hash["Total", { size: { value: total_size, unit: "Count" } }]

    max_latency = queues.values.max_by { |m| m[:latency][:value] }[:latency]
    summary["Max"] = { latency: max_latency }

    puts 'Sending metrics to CloudWatch'
    CloudwatchMetricCreator.new("Huginn/Sidekiq", "Queue Name", queues).create!
    CloudwatchMetricCreator.new("Huginn/Sidekiq", "Summary", summary).create!
    puts 'Done!'
  end
end
