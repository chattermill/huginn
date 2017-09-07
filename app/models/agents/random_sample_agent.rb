module Agents
  class RandomSampleAgent < Agent
    cannot_be_scheduled!

    description <<-MD
    The RandomSampleAgent takes events from other agents and passes on x% of them randomly sampled from each pull.

    `percent` is used to limit the percentage of events to be passed.

    `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
    that you anticipate passing without this Agent receiving an incoming Event.
   MD

    def default_options
      {
        'expected_receive_period_in_days' => "10",
        'percent' => 100
      }
    end

    def validate_options
      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end

      unless options['percent'].present? && options['percent'].to_i > 0 && options['percent'].to_i <= 100
        errors.add(:base, "The 'percent' option is required and must be an integer between 0 and 100")
      end
    end

    def working?
      last_receive_at && last_receive_at > options['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      percent = options['percent'].to_f / 100
      incoming_events.each do |event|
        create_event payload: event.payload if rand < percent
      end
    end

  end
end
