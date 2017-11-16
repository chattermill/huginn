class AddIndexToEvents < ActiveRecord::Migration[5.1]
  def change
    add_index(:events, :id, order: {id: :desc})
  end
end
