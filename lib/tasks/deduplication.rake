# frozen_string_literal: true

namespace :deduplication do

  desc 'Remove old tokens'
  task remove_old_tokens: :environment do
    DeduplicationToken.cleanup_expired!
    puts 'Done!'
  end
end
