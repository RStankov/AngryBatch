# frozen_string_literal: true

module AngryBatch::Batchable
  def self.included(base)
    base.after_perform do |job|
      AngryBatch::Handle.job_completed(job)
    end
  end
end
