# frozen_string_literal: true

class AddMetadataAndCountersToAngryBatchTables < ActiveRecord::Migration[7.0]
  def up
    change_table :angry_batch_batches do |t|
      begin
        t.jsonb :metadata, null: false, default: {}
      rescue NoMethodError
        t.json :metadata, null: false, default: {}
      end

      t.integer :completed_jobs_count, null: false, default: 0
      t.integer :failed_jobs_count, null: false, default: 0
    end

    change_column_default :angry_batch_batches, :state, from: 'scheduling', to: 'pending'

    execute "UPDATE angry_batch_batches SET state = 'pending' WHERE state = 'scheduling'"

    execute <<~SQL.squish
      UPDATE angry_batch_batches SET
        completed_jobs_count = (SELECT COUNT(*) FROM angry_batch_jobs WHERE angry_batch_jobs.batch_id = angry_batch_batches.id AND angry_batch_jobs.state = 'completed'),
        failed_jobs_count = (SELECT COUNT(*) FROM angry_batch_jobs WHERE angry_batch_jobs.batch_id = angry_batch_batches.id AND angry_batch_jobs.state = 'failed')
    SQL
  end

  def down
    change_column_default :angry_batch_batches, :state, from: 'pending', to: 'scheduling'

    remove_column :angry_batch_batches, :metadata
    remove_column :angry_batch_batches, :completed_jobs_count
    remove_column :angry_batch_batches, :failed_jobs_count
  end
end
