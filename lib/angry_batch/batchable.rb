# frozen_string_literal: true

module AngryBatch::Batchable
  def self.included(base)
    base.after_perform do |job|
      AngryBatch::Handle.job_completed(job)
    end

    base.after_discard do |job, exception|
      AngryBatch::Handle.job_failed(job, exception)
    end
  end

  attr_accessor :angry_batch_id

  def serialize
    super.merge('angry_batch_id' => angry_batch_id)
  end

  def deserialize(job_data)
    super
    self.angry_batch_id = job_data['angry_batch_id']
  end

  def batch
    return @batch if defined?(@batch)

    @batch = angry_batch_id && AngryBatch::Batch.find_by(id: angry_batch_id)
  end
end
