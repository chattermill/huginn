# frozen_string_literal: true
require 'aws-sdk-cloudwatch'

namespace :sidekiq do
  desc 'Send sidekiq queue metrics to Cloudwatch'
  task send_queue_metrics: :environment do
    time =  Time.now.utc.iso8601

    cloudwatch = Aws::CloudWatch::Client.new(access_key_id: ENV['AWS_ACCESS_KEY_ID'],
                                             secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
                                             region: ENV['AWS_REGION'])

    queues = Sidekiq::Queue.all.each_with_object({}) do |queue, hash|
      hash[queue.name] = {
        size: {value: queue.size, unit: 'Count'},
        latency: {value: queue.latency.to_i, unit: 'Seconds'}
      }
    end

    data = []
    queues.each do |queue_name, metrics|
      metrics.each do |metric_name, attrs|
        data.push({
          metric_name: metric_name.to_s.camelize,
          dimensions: [
            {
              name: "Queue Name",
              value: queue_name
            }
          ],
          value: attrs[:value],
          unit: attrs[:unit],
          timestamp: time,
        })
      end
    end

    cloudwatch.put_metric_data({
      namespace: "Huginn/Sidekiq",
      metric_data: data
    })

  end
end
