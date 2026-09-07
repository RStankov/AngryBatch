# frozen_string_literal: true

# == Schema Information
#
# Table name: angry_batch_batches
#
#  id                   :bigint(8)        not null, primary key
#  complete_handlers    :jsonb            not null
#  completed_jobs_count :integer          default(0), not null
#  failed_jobs_count    :integer          default(0), not null
#  failure_handlers     :jsonb            not null
#  finished_at          :datetime
#  jobs_count           :integer          default(0), not null
#  label                :string
#  metadata             :jsonb            not null
#  state                :string           default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_angry_batch_batches_on_state  (state)
#
class AngryBatch::Batch < ActiveRecord::Base
  self.table_name = 'angry_batch_batches'

  has_many :jobs, class_name: 'AngryBatch::Job', dependent: :delete_all

  enum :state, {
    pending: 'pending',
    completed: 'completed',
    failed: 'failed',
  }

  class << self
    def expired
      completed.where(updated_at: ...2.days.ago).or(failed.where(updated_at: ...4.weeks.ago)).or(pending.where(updated_at: ...4.weeks.ago))
    end
  end

  def enqueue(job_class, *, **)
    AngryBatch::Helper.assert_batchable(job_class)

    job = job_class.new(*, **)

    with_lock do
      raise AngryBatch::BatchFinishedError, "Batch #{id} is #{state}" unless pending?

      AngryBatch::Helper.add_job_to_batch(self, job)
    end

    AngryBatch::Helper.after_transaction do
      raise ActiveJob::EnqueueError, ["#{job_class} was not enqueued", job.enqueue_error&.message].compact.join(': ') unless job.enqueue
    end

    job
  end

  def metadata
    raw = read_attribute(:metadata)

    unless defined?(@metadata) && @metadata_raw == raw
      @metadata = ActiveJob::Arguments.deserialize([raw || {}]).first
      @metadata_raw = raw
    end

    @metadata
  end

  def pending_jobs_count
    jobs_count - completed_jobs_count - failed_jobs_count
  end

  def progress
    return 0 if jobs_count.zero?

    ((completed_jobs_count + failed_jobs_count) * 100 / jobs_count).clamp(0, 100)
  end

  def check_status_of_jobs
    handlers_to_enqueue = with_lock do
      return unless pending?
      return if jobs_count.zero?
      return unless pending_jobs_count <= 0

      self.finished_at = Time.current

      if failed_jobs_count.zero?
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
    error = nil

    handlers.each do |(job_class, job_arguments)|
      job = job_class.constantize.new(*ActiveJob::Arguments.deserialize(job_arguments || []))
      job.angry_batch_id = id if job.is_a?(AngryBatch::Batchable)

      raise ActiveJob::EnqueueError, "#{job_class} was not enqueued" unless job.enqueue
    rescue StandardError => e
      error ||= e
    end

    raise error if error
  end
end
