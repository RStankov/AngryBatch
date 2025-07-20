# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AngryBatch::Handle do
  describe '.job_completed' do
    it 'ignores when cant find a job with given id' do
      job = double job_id: 'none'

      expect { described_class.job_completed(job) }.not_to raise_error
    end

    it 'marks job and batch record as completed' do
      job = double job_id: 'done-job'

      record = create(:angry_batch_job, active_job_idx: job.job_id)

      described_class.job_completed(job)

      record.reload

      expect(record.state).to eq 'completed'
      expect(record.batch.state).to eq 'completed'
      expect(record.batch.finished_at).to be_present
    end

    it 'doesnt mark batch as completed when there are other jobs' do
      job = double job_id: 'done-job'

      batch = create(:angry_batch, state: :pending)

      record = create(:angry_batch_job, batch: batch, active_job_idx: job.job_id)
      create(:angry_batch_job, batch: batch)

      described_class.job_completed(job)

      record.reload

      expect(record.state).to eq 'completed'
      expect(record.batch.state).to eq 'pending'
    end
  end
end
