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
end
