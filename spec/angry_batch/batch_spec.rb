# frozen_string_literal: true

require 'spec_helper'

module AngryBatchTests
  class CompleteJob < ActiveJob::Base
  end

  class FailureJob < ActiveJob::Base
  end

  class MemberJob < ActiveJob::Base
    include AngryBatch::Batchable
  end

  class AbortsEnqueueJob < ActiveJob::Base
    include AngryBatch::Batchable

    before_enqueue { throw :abort }
  end
end

RSpec.describe AngryBatch::Batch do
  describe '#check_status_of_jobs' do
    it 'doesnt do anything when status isnt pending' do
      batch = create(:angry_batch, state: 'completed')

      create(:angry_batch_job, batch: batch, state: 'completed')

      batch.check_status_of_jobs

      expect(batch.state).to eq 'completed'
    end

    it 'doesnt do anything when there are uncompleted jobs' do
      batch = create(:angry_batch, state: 'pending')

      create(:angry_batch_job, batch: batch, state: 'completed')
      create(:angry_batch_job, batch: batch, state: 'pending')

      batch.check_status_of_jobs

      expect(batch.state).to eq 'pending'
    end

    it 'marks job as completed when all jobs are completed' do
      batch = create(:angry_batch, state: 'pending')

      create(:angry_batch_job, batch: batch, state: 'completed')

      batch.check_status_of_jobs

      expect(batch.state).to eq 'completed'
      expect(batch.finished_at).to be_present
    end

    it 'decides completion from counters without counting job records' do
      batch = create(:angry_batch, state: 'pending')

      create(:angry_batch_job, batch: batch, state: 'completed')

      queries = []
      callback = ->(*, payload) { queries << payload[:sql] }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        batch.check_status_of_jobs
      end

      expect(queries.grep(/COUNT\(/i)).to be_empty
      expect(batch.state).to eq 'completed'
    end

    it 'completes the batch when the counters have drifted past the job count' do
      batch = create(:angry_batch, state: 'pending')

      create(:angry_batch_job, batch: batch, state: 'completed')
      described_class.where(id: batch.id).update_all(completed_jobs_count: 2) # rubocop:disable Rails/SkipsModelValidations

      batch.reload.check_status_of_jobs

      expect(batch.state).to eq 'completed'
    end

    it 'enqueues complete handlers when complete' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob'], ['AngryBatchTests::CompleteJob', [1]], ['AngryBatchTests::CompleteJob', [2, 3]]], failure_handlers: [['AngryBatchTests::FailureJob']])

      create(:angry_batch_job, batch: batch, state: 'completed')

      batch.check_status_of_jobs

      expect(AngryBatchTests::CompleteJob).to have_been_enqueued.exactly(3).times
      expect(AngryBatchTests::CompleteJob).to have_been_enqueued.with(1)
      expect(AngryBatchTests::CompleteJob).to have_been_enqueued.with(2, 3)
      expect(AngryBatchTests::FailureJob).not_to have_been_enqueued
    end

    it 'enqueues handlers after releasing the database lock' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob']])
      create(:angry_batch_job, batch: batch, state: 'completed')

      call_sequence = []

      allow(batch).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        result = original.call(*args, &block)
        call_sequence << :lock_released
        result
      end

      allow_any_instance_of(AngryBatchTests::CompleteJob).to receive(:enqueue) do # rubocop:disable RSpec/AnyInstance
        call_sequence << :enqueue_called
      end

      batch.check_status_of_jobs

      expect(call_sequence).to eq %i(lock_released enqueue_called)
    end

    it 'only enqueues handlers once when called concurrently' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob']])
      create(:angry_batch_job, batch: batch, state: 'completed')

      stale_batch = described_class.find(batch.id)

      batch.check_status_of_jobs
      stale_batch.check_status_of_jobs

      expect(AngryBatchTests::CompleteJob).to have_been_enqueued.exactly(1).times
    end

    it 'enqueues the remaining handlers when one of them fails' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::NotLoadableJob'], ['AngryBatchTests::CompleteJob']])

      create(:angry_batch_job, batch: batch, state: 'completed')

      expect { batch.check_status_of_jobs }.to raise_error(NameError)

      expect(AngryBatchTests::CompleteJob).to have_been_enqueued
    end

    it 'enqueues failure handlers when failed' do
      batch = create(:angry_batch, state: 'pending', failure_handlers: [['AngryBatchTests::FailureJob', [1]], ['AngryBatchTests::FailureJob', [2, 3]]], complete_handlers: [['AngryBatchTests::CompleteJob']])

      create(:angry_batch_job, batch: batch, state: 'failed')

      batch.check_status_of_jobs

      expect(AngryBatchTests::FailureJob).to have_been_enqueued.with(1)
      expect(AngryBatchTests::FailureJob).to have_been_enqueued.with(2, 3)
      expect(AngryBatchTests::CompleteJob).not_to have_been_enqueued
    end
  end

  describe '#enqueue' do
    it 'doesnt allow non batchable jobs' do
      batch = create(:angry_batch, state: 'pending')

      expect { batch.enqueue AngryBatchTests::CompleteJob }.to raise_error(AngryBatch::BatchArgumentError, /must include AngryBatch::Batchable/)

      expect(batch.jobs.count).to eq 0
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    it 'raises when the batch is completed' do
      batch = create(:angry_batch, state: 'completed')

      expect { batch.enqueue AngryBatchTests::MemberJob }.to raise_error(AngryBatch::BatchFinishedError, /is completed/)

      expect(batch.jobs.count).to eq 0
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    it 'raises when the batch is failed' do
      batch = create(:angry_batch, state: 'failed')

      expect { batch.enqueue AngryBatchTests::MemberJob }.to raise_error(AngryBatch::BatchFinishedError, /is failed/)

      expect(batch.jobs.count).to eq 0
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    it 'creates a job record and enqueues the job with the batch id' do
      batch = create(:angry_batch, state: 'pending')

      job = batch.enqueue AngryBatchTests::MemberJob, 1, 2

      expect(job).to be_a AngryBatchTests::MemberJob

      expect(batch.reload.jobs_count).to eq 1
      expect(batch.jobs.first).to have_attributes(
        state: 'pending',
        active_job_idx: job.job_id,
        active_job_class: 'AngryBatchTests::MemberJob',
        active_job_arguments: [1, 2],
      )

      expect(AngryBatchTests::MemberJob).to have_been_enqueued.with(1, 2)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last['angry_batch_id']).to eq batch.id
    end

    it 'raises when the job is not enqueued' do
      batch = create(:angry_batch, state: 'pending')

      expect { batch.enqueue AngryBatchTests::AbortsEnqueueJob }.to raise_error(ActiveJob::EnqueueError, /AbortsEnqueueJob/)
    end

    it 'raises when the adapter raises' do
      batch = create(:angry_batch, state: 'pending')

      allow_any_instance_of(AngryBatchTests::MemberJob).to receive(:enqueue).and_raise(RuntimeError, 'broker is down') # rubocop:disable RSpec/AnyInstance

      expect { batch.enqueue AngryBatchTests::MemberJob }.to raise_error('broker is down')
    end

    it 'does not settle the batch when a job is not enqueued' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob']], failure_handlers: [['AngryBatchTests::FailureJob']])

      create(:angry_batch_job, batch: batch, state: 'completed')

      expect { batch.enqueue AngryBatchTests::AbortsEnqueueJob }.to raise_error(ActiveJob::EnqueueError)

      expect(batch.reload.state).to eq 'pending'
      expect(AngryBatchTests::CompleteJob).not_to have_been_enqueued
      expect(AngryBatchTests::FailureJob).not_to have_been_enqueued
    end

    it 'prevents a stale instance from completing the batch' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob']])
      create(:angry_batch_job, batch: batch, state: 'completed')

      stale_batch = described_class.find(batch.id)

      batch.enqueue AngryBatchTests::MemberJob

      stale_batch.check_status_of_jobs

      expect(stale_batch.state).to eq 'pending'
      expect(AngryBatchTests::CompleteJob).not_to have_been_enqueued
    end

    it 'enqueues the job after releasing the database lock' do
      batch = create(:angry_batch, state: 'pending')

      call_sequence = []

      allow(batch).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        result = original.call(*args, &block)
        call_sequence << :lock_released
        result
      end

      allow_any_instance_of(AngryBatchTests::MemberJob).to receive(:enqueue) do # rubocop:disable RSpec/AnyInstance
        call_sequence << :enqueue_called
      end

      batch.enqueue AngryBatchTests::MemberJob

      expect(call_sequence).to eq %i(lock_released enqueue_called)
    end
  end

  describe '#metadata' do
    it 'is refreshed on reload' do
      batch = create(:angry_batch, metadata: ActiveJob::Arguments.serialize([{ step: 1 }]).first)

      expect(batch.metadata).to eq(step: 1)

      described_class.where(id: batch.id).update_all(metadata: ActiveJob::Arguments.serialize([{ step: 2 }]).first) # rubocop:disable Rails/SkipsModelValidations

      expect(batch.reload.metadata).to eq(step: 2)
    end
  end

  describe '#pending_jobs_count' do
    it 'counts the jobs that have not finished' do
      batch = create(:angry_batch)

      create(:angry_batch_job, batch: batch, state: 'completed')
      create(:angry_batch_job, batch: batch, state: 'failed')
      create(:angry_batch_job, batch: batch, state: 'pending')

      expect(batch.reload.pending_jobs_count).to eq 1
    end
  end

  describe '#progress' do
    it 'returns the finished percentage' do
      batch = create(:angry_batch)

      create(:angry_batch_job, batch: batch, state: 'completed')
      create(:angry_batch_job, batch: batch, state: 'failed')
      create(:angry_batch_job, batch: batch, state: 'pending')
      create(:angry_batch_job, batch: batch, state: 'pending')

      expect(batch.reload.progress).to eq 50
    end

    it 'returns 0 when there are no jobs' do
      expect(create(:angry_batch).progress).to eq 0
    end

    it 'never exceeds 100 when the counters drift' do
      batch = create(:angry_batch)

      create(:angry_batch_job, batch: batch, state: 'completed')
      described_class.where(id: batch.id).update_all(completed_jobs_count: 2) # rubocop:disable Rails/SkipsModelValidations

      expect(batch.reload.progress).to eq 100
    end
  end

  describe '.expired' do
    it 'selects completed tasks from more than 2 days ago' do
      expired = create(:angry_batch, state: 'completed', updated_at: 2.days.ago)
      _not_expired = create(:angry_batch, state: 'completed', updated_at: 1.day.ago)

      expect(described_class.expired).to eq [expired]
    end

    it 'selects failed tasks from more than 2 weeks ago' do
      expired = create(:angry_batch, state: 'failed', updated_at: 4.weeks.ago)
      _not_expired = create(:angry_batch, state: 'failed', updated_at: 1.week.ago)

      expect(described_class.expired).to eq [expired]
    end

    it 'selects still pending tasks from more than 2 weeks ago' do
      expired = create(:angry_batch, state: 'pending', updated_at: 4.weeks.ago)
      _not_expired = create(:angry_batch, state: 'pending', updated_at: 1.week.ago)

      expect(described_class.expired).to eq [expired]
    end
  end
end
