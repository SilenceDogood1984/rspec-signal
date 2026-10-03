# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name, null: false
    t.string :email, null: false
    t.string :role, null: false, default: "member"
  end

  create_table :projects, force: true do |t|
    t.string :name, null: false
    t.references :owner, null: false
    t.boolean :archived, null: false, default: false
    t.integer :budget_cents, null: false, default: 0
    t.timestamps
  end

  create_table :audit_entries, force: true do |t|
    t.references :project
    t.string :action, null: false
    t.timestamps
  end

  create_table :deliveries, force: true do |t|
    t.references :project, null: false
    t.string :status, null: false
    t.timestamps
  end
end
