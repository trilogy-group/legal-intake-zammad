# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CreateTicketSharedAccesses < ActiveRecord::Migration[7.2]
  def change
    create_table :ticket_shared_accesses do |t|
      t.references :ticket,       null: false, foreign_key: true
      t.references :user,         null: false, foreign_key: { to_table: :users }
      t.references :created_by,   null: false, foreign_key: { to_table: :users }
      t.references :updated_by,   null: false, foreign_key: { to_table: :users }
      t.timestamps limit: 3, null: false
    end

    add_index :ticket_shared_accesses, %i[ticket_id user_id], unique: true
  end
end
