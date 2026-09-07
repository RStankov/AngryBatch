# frozen_string_literal: true

module AngryBatch::Handle
  extend self

  def job_completed(job)
    finish(job, state: 'completed')
  end

  def job_failed(job, exception = nil)
    finish(job, state: 'failed', error_message: exception&.message)
  end

  private

  def finish(job, state:, **attributes)
    record = AngryBatch::Job.find_by(active_job_idx: job.job_id)

    return if record.blank?

    record.with_lock do
      if record.pending?
        record.update!(state: state, **attributes)
        AngryBatch::Batch.increment_counter(:"#{state}_jobs_count", record.batch_id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    record.batch&.check_status_of_jobs
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
