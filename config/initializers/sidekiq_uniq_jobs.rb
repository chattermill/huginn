# frozen_string_literal: true

require 'sidekiq-unique-jobs'

Sidekiq.default_worker_options = {
  unique: :until_executed,
  unique_args: lambda { |args|
    r = args.first.except('job_id')
    # this ensure to be unique by adding the 'make_unique' argument
    # to all agents other than AgentCheckJob
    r[:make_unique] = SecureRandom.uuid unless r['job_class'] == 'AgentCheckJob'
    [r]
  }
}
SidekiqUniqueJobs.config.unique_args_enabled = true
