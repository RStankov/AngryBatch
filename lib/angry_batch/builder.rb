# frozen_string_literal: true

class AngryBatch::Builder
  def initialize(label: nil)
    @batch = AngryBatch::Batch.new(
      label: label,
      state: 'scheduling',
      complete_handlers: [],
      failure_handlers: [],
    )
    @jobs = []
  end

  def performed?
    @batch.persisted?
  end

  delegate :empty?, to: :@jobs

  def on_complete(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?
    raise AngryBatch::BatchArgumentError, "#{job_class} be a subclass of ActiveJob::Base" unless job_class.is_a?(Class) && job_class < ActiveJob::Base

    @batch.complete_handlers << [job_class, job_class.new(*, **).serialize['arguments']]
  end

  def on_failure(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?
    raise AngryBatch::BatchArgumentError, "#{job_class} be a subclass of ActiveJob::Base" unless job_class.is_a?(Class) && job_class < ActiveJob::Base

    @batch.failure_handlers << [job_class, job_class.new(*, **).serialize['arguments']]
  end

  def enqueue(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' unless @batch.new_record?
    raise AngryBatch::BatchArgumentError, "#{job_class} be a subclass of ActiveJob::Base" unless job_class.is_a?(Class) && job_class < ActiveJob::Base
    raise AngryBatch::BatchArgumentError, "#{job_class} must include AngryBatch::Batchable" unless job_class.included_modules.include?(AngryBatch::Batchable)

    @jobs << job_class.new(*, **)
  end

  def perform_later
    raise AngryBatch::BatchArgumentError, 'Batch is empty' if empty?
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?

    @batch.save!

    @jobs.each do |job|
      @batch.jobs.create!(
        active_job_idx: job.job_id,
        active_job_class: job.class.name,
        active_job_arguments: job.serialize['arguments'],
      )

      job.enqueue
    end

    @batch.update!(state: 'pending')
    @batch.reload
    @batch.check_status_of_jobs
  end
end
