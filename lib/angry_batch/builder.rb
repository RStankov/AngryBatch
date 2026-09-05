# frozen_string_literal: true

class AngryBatch::Builder
  def initialize(label: nil, metadata: {})
    @metadata = ActiveJob::Arguments.serialize([metadata || {}]).first
    @batch = AngryBatch::Batch.new(
      label: label,
      metadata: @metadata,
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

    AngryBatch::Helper.assert_job_class(job_class)

    @batch.complete_handlers << [job_class, job_class.new(*, **).serialize['arguments']]
  end

  def on_failure(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?

    AngryBatch::Helper.assert_job_class(job_class)

    @batch.failure_handlers << [job_class, job_class.new(*, **).serialize['arguments']]
  end

  def enqueue(job_class, *, **)
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?

    AngryBatch::Helper.assert_batchable(job_class)

    @jobs << job_class.new(*, **)
  end

  def perform_later
    raise AngryBatch::BatchArgumentError, 'Batch is empty' if empty?
    raise AngryBatch::BatchArgumentError, 'Batch is already running' if performed?

    ActiveRecord::Base.transaction(requires_new: true) do
      @batch.save!

      @jobs.each { |job| AngryBatch::Helper.add_job_to_batch(@batch, job) }
    end

    @performed = true

    AngryBatch::Helper.after_transaction do
      @jobs.each do |job|
        raise ActiveJob::EnqueueError, ["#{job.class.name} was not enqueued", job.enqueue_error&.message].compact.join(': ') unless job.enqueue
      end
    end

    @batch
  rescue StandardError
    unless @performed
      @batch = AngryBatch::Batch.new(
        label: @batch.label,
        metadata: @metadata,
        complete_handlers: @batch.complete_handlers,
        failure_handlers: @batch.failure_handlers,
      )
    end
    raise
  end
end
