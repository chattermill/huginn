class ChangeDeduplicationTokens < ActiveRecord::Migration[5.1]
  def change
    change_table :deduplication_tokens do |t|
      t.datetime :created_at
      t.index :created_at
    end
  end
end
