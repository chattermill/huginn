class AddEventIdToDeduplicationTokens < ActiveRecord::Migration[5.1]
  def change
    change_table :deduplication_tokens do |t|
      t.integer :event_id
      t.index :event_id
    end

    add_foreign_key :deduplication_tokens, :events
  end
end
