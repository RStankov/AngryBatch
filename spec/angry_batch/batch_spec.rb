# frozen_string_literal: true

require 'spec_helper'

module AngryBatchTests
  class CompleteJob < ActiveJob::Base
  end

  class FailureJob < ActiveJob::Base
  end

  class AnotherCompleteJob < ActiveJob::Base
  end
end

RSpec.describe AngryBatch::Batch do
  describe '#check_status_of_jobs' do
    it 'doesnt do anything when status isnt pending' do
      batch = create(:angry_batch, state: 'scheduling')

      create(:angry_batch_job, batch: batch, state: 'completed')

      batch.check_status_of_jobs

      expect(batch.state).to eq 'scheduling'
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

    it 'enqueues complete handlers when complete' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob'], ['AngryBatchTests::CompleteJob', [1]], ['AngryBatchTests::CompleteJob', [2, 3]]], failure_handlers: [['FailureJob']])

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

      allow(AngryBatchTests::CompleteJob).to receive(:perform_later) do
        call_sequence << :enqueue_called
      end

      batch.check_status_of_jobs

      expect(call_sequence).to eq [:lock_released, :enqueue_called]
    end

    it 'only enqueues handlers once when called concurrently' do
      batch = create(:angry_batch, state: 'pending', complete_handlers: [['AngryBatchTests::CompleteJob']])
      create(:angry_batch_job, batch: batch, state: 'completed')

      stale_batch = AngryBatch::Batch.find(batch.id)

      batch.check_status_of_jobs
      stale_batch.check_status_of_jobs

      expect(AngryBatchTests::CompleteJob).to have_been_enqueued.exactly(1).times
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
