# frozen_string_literal: true

module AngryBatch::Handle
  extend self

  def job_completed(job)
    record = AngryBatch::Job.find_by(active_job_idx: job.job_id)

    return if record.blank?

    record.with_lock do
      record.update!(state: 'completed')
    end

    record.batch.check_status_of_jobs
  end
end
