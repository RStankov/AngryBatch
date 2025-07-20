# frozen_string_literal: true

class AngryBatch::CleanupCronJob < ActiveJob::Base
  def perform
    AngryBatch::Batch.expired.destroy_all
  end
end
