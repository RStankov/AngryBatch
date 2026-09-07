# frozen_string_literal: true

module AngryBatch::Helper
  extend self

  def assert_job_class(job_class)
    return if job_class.is_a?(Class) && job_class < ActiveJob::Base

    raise AngryBatch::BatchArgumentError, "#{job_class} must be a subclass of ActiveJob::Base"
  end

  def assert_batchable(job_class)
    assert_job_class(job_class)

    return if job_class.included_modules.include?(AngryBatch::Batchable)

    raise AngryBatch::BatchArgumentError, "#{job_class} must include AngryBatch::Batchable"
  end

  def add_job_to_batch(batch, job)
    job.angry_batch_id = batch.id

    batch.jobs.create!(
      active_job_idx: job.job_id,
      active_job_class: job.class.name,
      active_job_arguments: job.serialize['arguments'],
    )
  end

  # NOTE(rstankov): pushing after the commit keeps workers from seeing a job
  # before its record. Rails < 7.2 has no hook for it and pushes immediately.
  if ActiveRecord.respond_to?(:after_all_transactions_commit)
    def after_transaction(&)
      ActiveRecord.after_all_transactions_commit(&)
    end
  else
    def after_transaction
      yield
    end
  end
end
