class AddIndexToEvents < ActiveRecord::Migration[5.1]
  def change
    add_index(:events, :id, order: {id: :desc})
    add_index(:events, :agent_id)
  end
end
