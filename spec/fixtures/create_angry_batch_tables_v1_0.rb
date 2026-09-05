# frozen_string_literal: true

class CreateAngryBatchTables < ActiveRecord::Migration[7.0]
  def change
    create_table :angry_batch_batches do |t|
      begin
        t.jsonb :complete_handlers, null: false, default: []
        t.jsonb :failure_handlers, null: false, default: []
      rescue NoMethodError
        t.json :complete_handlers, null: false, default: []
        t.json :failure_handlers, null: false, default: []
      end

      t.datetime :finished_at
      t.integer  :jobs_count, null: false, default: 0
      t.string   :label
      t.string   :state, null: false, default: 'scheduling'

      t.timestamps
    end

    add_index :angry_batch_batches, :state

    create_table :angry_batch_jobs do |t|
      t.references :batch, null: false, foreign_key: { to_table: :angry_batch_batches }, index: false
      t.string     :active_job_class, null: false
      t.string     :active_job_idx, null: false

      begin
        t.jsonb :active_job_arguments
      rescue NoMethodError
        t.json :active_job_arguments
      end

      t.string     :error_message
      t.string     :state, null: false, default: 'pending'

      t.timestamps
    end

    add_index :angry_batch_jobs, :active_job_idx, unique: true
    add_index :angry_batch_jobs, %i(batch_id state)
  end
end
