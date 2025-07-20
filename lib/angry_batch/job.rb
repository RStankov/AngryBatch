# frozen_string_literal: true

# == Schema Information
#
# Table name: angry_batch_jobs
#
#  id                   :bigint(8)        not null, primary key
#  active_job_arguments :jsonb
#  active_job_class     :string           not null
#  active_job_idx       :string           not null
#  error_message        :string
#  state                :string           default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  batch_id             :bigint(8)        not null
#
# Indexes
#
#  index_angry_batch_jobs_on_active_job_idx      (active_job_idx) UNIQUE
#  index_angry_batch_jobs_on_batch_id_and_state  (batch_id,state)
#
# Foreign Keys
#
#  fk_rails_...  (batch_id => angry_batch_batches.id)
#
class AngryBatch::Job < ActiveRecord::Base
  self.table_name = 'angry_batch_jobs'

  belongs_to :batch, class_name: 'AngryBatch::Batch', counter_cache: true

  enum :state, {
    pending: 'pending',
    completed: 'completed',
    failed: 'failed',
  }

  scope :finished, -> { where(state: %i(completed failed)) }
end
