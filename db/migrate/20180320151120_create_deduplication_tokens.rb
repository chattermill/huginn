class CreateDeduplicationTokens < ActiveRecord::Migration[5.1]
  def change
    create_table :deduplication_tokens do |t|
      t.string :token
      t.integer :agent_id
    end

    add_index :deduplication_tokens, [:agent_id, :token]
    add_index :deduplication_tokens, :agent_id
  end
end
