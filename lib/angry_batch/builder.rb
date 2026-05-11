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
    @performed = false
  end

  def performed?
    @performed
  end

  delegate :empty?, to: :@jobs

  def on_complete(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?
    raise AngryBatch::BatchArgumentError, "#{job_class} must be a subclass of ActiveJob::Base" unless job_class.is_a?(Class) && job_class < ActiveJob::Base

    @batch.complete_handlers << [job_class, job_class.new(*, **).serialize['arguments']]
  end

  def on_failure(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?
    raise AngryBatch::BatchArgumentError, "#{job_class} must be a subclass of ActiveJob::Base" unless job_class.is_a?(Class) && job_class < ActiveJob::Base

    @batch.failure_handlers << [job_class, job_class.new(*, **).serialize['arguments']]
  end

  def enqueue(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?
    raise AngryBatch::BatchArgumentError, "#{job_class} must be a subclass of ActiveJob::Base" unless job_class.is_a?(Class) && job_class < ActiveJob::Base
    raise AngryBatch::BatchArgumentError, "#{job_class} must include AngryBatch::Batchable" unless job_class.included_modules.include?(AngryBatch::Batchable)

    @jobs << job_class.new(*, **)
  end

  def perform_later
    raise AngryBatch::BatchArgumentError, 'Batch is empty' if empty?
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?

    ActiveRecord::Base.transaction(requires_new: true) do
      @batch.save!

      @jobs.each do |job|
        @batch.jobs.create!(
          active_job_idx: job.job_id,
          active_job_class: job.class.name,
          active_job_arguments: job.serialize['arguments'],
        )
      end

      @batch.update!(state: 'pending')
    end

    @performed = true
    @jobs.each(&:enqueue)
    @batch.check_status_of_jobs
  rescue
    unless @performed
      @batch = AngryBatch::Batch.new(
        label: @batch.label,
        state: 'scheduling',
        complete_handlers: @batch.complete_handlers,
        failure_handlers: @batch.failure_handlers,
      )
    end
    raise
  end
end
