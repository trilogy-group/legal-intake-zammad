# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CreateTicketSharedAccesses < ActiveRecord::Migration[8.0]
  def change
    create_table :ticket_shared_accesses, id: :integer do |t|
      t.references :ticket,       null: false, foreign_key: true, type: :integer
      t.references :user,         null: false, foreign_key: { to_table: :users }, type: :integer
      t.references :created_by,   null: false, foreign_key: { to_table: :users }, type: :integer
      t.references :updated_by,   null: false, foreign_key: { to_table: :users }, type: :integer
      t.timestamps limit: 3, null: false
    end

    add_index :ticket_shared_accesses, %i[ticket_id user_id], unique: true
  end
end
