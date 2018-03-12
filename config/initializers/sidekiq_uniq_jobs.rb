# frozen_string_literal: true

require 'sidekiq-unique-jobs'

Sidekiq.default_worker_options = {
  unique: :until_executed,
  unique_across_workers: true,
  unique_args: lambda { |args|
    if args.first['job_class'] == 'AgentCheckJob'
      [args.first.except('job_id')]
    else
      [args.first]
    end

  }
}
SidekiqUniqueJobs.config.unique_args_enabled = true
