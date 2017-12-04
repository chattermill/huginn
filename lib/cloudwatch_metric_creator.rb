# frozen_string_literal: true

require 'aws-sdk-cloudwatch'

class CloudwatchMetricCreator
  attr_reader :namespace, :dimension_name, :data

  def initialize(namespace, dimension_name, data)
    @namespace = namespace
    @dimension_name = dimension_name
    @data = data
  end

  def create!
    cloudwatch.put_metric_data({
      namespace: namespace,
      metric_data: build_metric_data
    })
  end

  private

  def build_metric_data
    time =  Time.now.utc.iso8601
    metrics_data = []
    data.each do |dimension, metrics|
      metrics.each do |metric_name, attrs|
        metrics_data.push(
          metric_name: metric_name.to_s.camelize,
          dimensions: [
            {
              name: dimension_name,
              value: dimension
            }
          ],
          value: attrs[:value],
          unit: attrs[:unit],
          timestamp: time
        )
      end
    end
    metrics_data
  end

  def cloudwatch
    Aws::CloudWatch::Client.new(access_key_id: ENV['AWS_ACCESS_KEY_ID'],
                                secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
                                region: ENV['AWS_REGION'])
  end
end
