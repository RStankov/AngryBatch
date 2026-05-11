# frozen_string_literal: true

# == Schema Information
#
# Table name: angry_batch_batches
#
#  id                :bigint(8)        not null, primary key
#  complete_handlers :jsonb            not null
#  failure_handlers  :jsonb            not null
#  finished_at       :datetime
#  jobs_count        :integer          default(0), not null
#  label             :string
#  state             :string           default("scheduling"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_angry_batch_batches_on_state  (state)
#
class AngryBatch::Batch < ActiveRecord::Base
  self.table_name = 'angry_batch_batches'

  has_many :jobs, class_name: 'AngryBatch::Job', dependent: :delete_all

  enum :state, {
    scheduling: 'scheduling',
    pending: 'pending',
    completed: 'completed',
    failed: 'failed',
  }

  class << self
    def expired
      completed.where(updated_at: ...2.days.ago)
        .or(failed.where(updated_at: ...4.weeks.ago))
        .or(pending.where(updated_at: ...4.weeks.ago))
    end
  end

  def check_status_of_jobs
    handlers_to_enqueue = with_lock do
      return unless pending?
      return unless jobs_count == jobs.finished.count

      self.finished_at = Time.current

      if jobs.failed.none?
        update! state: 'completed'
        complete_handlers
      else
        update! state: 'failed'
        failure_handlers
      end
    end

    enqueue_handlers(handlers_to_enqueue)
  end

  private

  def enqueue_handlers(handlers)
    handlers.each do |(job_class, job_arguments)|
      job_class.constantize.perform_later(*ActiveJob::Arguments.deserialize(job_arguments || []))
    end
  end
end
