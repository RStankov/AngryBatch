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

    it 'handles record deleted between find and lock in job_completed' do
      job = double job_id: 'done-job'

      create(:angry_batch_job, active_job_idx: job.job_id)

      allow_any_instance_of(AngryBatch::Job).to receive(:with_lock).and_raise(ActiveRecord::RecordNotFound) # rubocop:disable RSpec/AnyInstance

      expect { described_class.job_completed(job) }.not_to raise_error
    end

    it 'handles batch deleted after lock released in job_completed' do
      job = double job_id: 'done-job'

      create(:angry_batch_job, active_job_idx: job.job_id)

      allow_any_instance_of(AngryBatch::Job).to receive(:batch).and_return(nil) # rubocop:disable RSpec/AnyInstance

      expect { described_class.job_completed(job) }.not_to raise_error
    end
  end

  describe '.job_failed' do
    it 'ignores when cant find a job with given id' do
      job = double job_id: 'none'

      expect { described_class.job_failed(job) }.not_to raise_error
    end

    it 'marks job and batch record as failed' do
      job = double job_id: 'failed-job'

      record = create(:angry_batch_job, active_job_idx: job.job_id)

      described_class.job_failed(job)

      record.reload

      expect(record.state).to eq 'failed'
      expect(record.batch.state).to eq 'failed'
      expect(record.batch.finished_at).to be_present
    end

    it 'stores the error message' do
      job = double job_id: 'failed-job'

      record = create(:angry_batch_job, active_job_idx: job.job_id)

      described_class.job_failed(job, RuntimeError.new('something went wrong'))

      record.reload

      expect(record.error_message).to eq 'something went wrong'
    end

    it 'does not overwrite a completed job as failed' do
      job = double(job_id: 'completed-job')

      record = create(:angry_batch_job, active_job_idx: job.job_id)

      described_class.job_completed(job)

      expect(record.reload.state).to eq 'completed'

      described_class.job_failed(job, RuntimeError.new('spurious callback error'))

      expect(record.reload.state).to eq 'completed'
      expect(record.batch.reload.state).to eq 'completed'
    end

    it 'handles record deleted between find and lock in job_failed' do
      job = double job_id: 'failed-job'

      create(:angry_batch_job, active_job_idx: job.job_id)

      allow_any_instance_of(AngryBatch::Job).to receive(:with_lock).and_raise(ActiveRecord::RecordNotFound) # rubocop:disable RSpec/AnyInstance

      expect { described_class.job_failed(job) }.not_to raise_error
    end

    it 'handles batch deleted after lock released in job_failed' do
      job = double job_id: 'failed-job'

      create(:angry_batch_job, active_job_idx: job.job_id)

      allow_any_instance_of(AngryBatch::Job).to receive(:batch).and_return(nil) # rubocop:disable RSpec/AnyInstance

      expect { described_class.job_failed(job) }.not_to raise_error
    end

    it 'doesnt mark batch as failed when there are other pending jobs' do
      job = double job_id: 'failed-job'

      batch = create(:angry_batch, state: :pending)

      record = create(:angry_batch_job, batch: batch, active_job_idx: job.job_id)
      create(:angry_batch_job, batch: batch)

      described_class.job_failed(job)

      record.reload

      expect(record.state).to eq 'failed'
      expect(record.batch.state).to eq 'pending'
    end
  end
end
