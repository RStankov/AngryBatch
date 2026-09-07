# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AddMetadataAndCountersToAngryBatchTables do
  it 'adds the columns and backfills the counters on a 1.0 schema' do
    described_class.new.migrate(:down)
    AngryBatch::Batch.reset_column_information

    batch = AngryBatch::Batch.create!(state: 'pending', complete_handlers: [], failure_handlers: [])
    AngryBatch::Job.create!(batch: batch, active_job_idx: '1', active_job_class: 'FakeJob', state: 'completed')
    AngryBatch::Job.create!(batch: batch, active_job_idx: '2', active_job_class: 'FakeJob', state: 'failed')
    AngryBatch::Job.create!(batch: batch, active_job_idx: '3', active_job_class: 'FakeJob', state: 'pending')

    described_class.new.migrate(:up)
    AngryBatch::Batch.reset_column_information

    expect(batch.reload).to have_attributes(jobs_count: 3, completed_jobs_count: 1, failed_jobs_count: 1, metadata: {})
  ensure
    AngryBatch::Batch.reset_column_information

    unless AngryBatch::Batch.column_names.include?('failed_jobs_count')
      described_class.new.migrate(:up)
      AngryBatch::Batch.reset_column_information
    end
  end
end
