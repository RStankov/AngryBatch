# frozen_string_literal: true

require 'spec_helper'

module AngryBatchTests
  class AlwaysComplete1Job < ActiveJob::Base
    include AngryBatch::Batchable

    def perform(_arg = nil)
      # NOTE(rstankov): Do what ever
    end
  end

  class AlwaysComplete2Job < ActiveJob::Base
    include AngryBatch::Batchable

    def perform(_arg = nil)
      # NOTE(rstankov): Do what ever
    end
  end

  class AlwaysFailJob < ActiveJob::Base
    include AngryBatch::Batchable

    discard_on StandardError

    def perform
      raise StandardError, 'something went wrong'
    end
  end

  class BatchCompletedJob < ActiveJob::Base
    def perform(_arg = nil, arg2: nil)
      # NOTE(rstankov): Do what ever
    end
  end

  class BatchFailedJob < ActiveJob::Base
    def perform
      # NOTE(rstankov): Do what ever
    end
  end

  SEEN_BATCHES = [] # rubocop:disable Style/MutableConstant

  class RecordsBatchJob < ActiveJob::Base
    include AngryBatch::Batchable

    def perform
      SEEN_BATCHES << batch
    end
  end

  class RecordsMetadataJob < ActiveJob::Base
    include AngryBatch::Batchable

    def perform
      SEEN_BATCHES << batch.metadata[:mode]
    end
  end

  class SpawnJob < ActiveJob::Base
    include AngryBatch::Batchable

    def perform(children = [])
      children.each { |grandchildren| batch.enqueue SpawnJob, grandchildren }
    end
  end

  class SpawnThenFailJob < ActiveJob::Base
    include AngryBatch::Batchable

    discard_on StandardError

    def perform
      batch.enqueue AlwaysComplete1Job
      batch.enqueue AlwaysComplete1Job

      raise StandardError, 'parent failed'
    end
  end

  class EnqueuesIntoBatchHandlerJob < ActiveJob::Base
    include AngryBatch::Batchable

    def perform
      batch.enqueue AlwaysComplete1Job
    end
  end
end

RSpec.describe AngryBatch do
  before { AngryBatchTests::SEEN_BATCHES.clear }

  describe 'batch access from jobs' do
    it 'exposes the batch inside a job', active_job: :inline do
      batch = described_class.new(label: 'test')
      batch.enqueue AngryBatchTests::RecordsBatchJob
      batch.perform_later

      record = described_class::Batch.find_by! label: 'test'

      expect(AngryBatchTests::SEEN_BATCHES).to eq [record]
    end

    it 'exposes metadata inside a job', active_job: :inline do
      batch = described_class.new(label: 'test', metadata: { mode: :full })
      batch.enqueue AngryBatchTests::RecordsMetadataJob
      batch.perform_later

      expect(AngryBatchTests::SEEN_BATCHES).to eq [:full]
    end

    it 'exposes nil when the job runs outside of a batch', active_job: :inline do
      AngryBatchTests::RecordsBatchJob.perform_later

      expect(AngryBatchTests::SEEN_BATCHES).to eq [nil]
    end

    it 'exposes the batch to handlers that include Batchable', active_job: :inline do
      batch = described_class.new(label: 'test')
      batch.on_complete AngryBatchTests::RecordsBatchJob
      batch.enqueue AngryBatchTests::AlwaysComplete1Job
      batch.perform_later

      record = described_class::Batch.find_by! label: 'test'

      expect(AngryBatchTests::SEEN_BATCHES).to eq [record]
      expect(record.state).to eq 'completed'
      expect(record).to have_attributes(jobs_count: 1, completed_jobs_count: 1, failed_jobs_count: 0)
      expect(record.jobs.count).to eq 1
    end
  end

  describe 'transactions', if: ActiveRecord.respond_to?(:after_all_transactions_commit) do
    it 'pushes jobs only once the surrounding transaction commits' do
      queue = described_class.new(label: 'test')
      queue.enqueue AngryBatchTests::AlwaysComplete1Job

      ActiveRecord::Base.transaction do
        queue.perform_later

        expect(described_class::Batch.find_by!(label: 'test').jobs_count).to eq 1
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end

      expect(AngryBatchTests::AlwaysComplete1Job).to have_been_enqueued
    end

    it 'pushes nothing when the surrounding transaction rolls back' do
      queue = described_class.new(label: 'test')
      queue.enqueue AngryBatchTests::AlwaysComplete1Job

      ActiveRecord::Base.transaction do
        queue.perform_later
        raise ActiveRecord::Rollback
      end

      expect(described_class::Batch.find_by(label: 'test')).to be_nil
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  describe 'enqueuing from inside a job' do
    it 'tracks nested jobs and completes once after all of them', active_job: :inline do
      batch = described_class.new(label: 'test')
      batch.on_complete AngryBatchTests::RecordsBatchJob
      batch.enqueue AngryBatchTests::SpawnJob, [[[]], []]
      batch.perform_later

      record = described_class::Batch.find_by! label: 'test'

      expect(record.state).to eq 'completed'
      expect(record).to have_attributes(jobs_count: 4, completed_jobs_count: 4, failed_jobs_count: 0, progress: 100)
      expect(AngryBatchTests::SEEN_BATCHES).to eq [record]
    end

    it 'fails the batch after children finish when the parent raises', active_job: :inline do
      batch = described_class.new(label: 'test')
      batch.on_complete AngryBatchTests::BatchCompletedJob
      batch.on_failure AngryBatchTests::RecordsBatchJob
      batch.enqueue AngryBatchTests::SpawnThenFailJob
      batch.perform_later

      record = described_class::Batch.find_by! label: 'test'

      expect(record.state).to eq 'failed'
      expect(record).to have_attributes(jobs_count: 3, completed_jobs_count: 2, failed_jobs_count: 1)
      expect(record.jobs.failed.first.error_message).to eq 'parent failed'
      expect(AngryBatchTests::SEEN_BATCHES).to eq [record]
      expect(AngryBatchTests::BatchCompletedJob).not_to have_been_performed
    end

    it 'raises when a handler tries to add jobs to the finished batch', active_job: :inline do
      batch = described_class.new(label: 'test')
      batch.on_complete AngryBatchTests::EnqueuesIntoBatchHandlerJob
      batch.enqueue AngryBatchTests::AlwaysComplete1Job

      expect { batch.perform_later }.to raise_error(AngryBatch::BatchFinishedError)
    end
  end

  describe 'batching' do
    it 'can call on complete job when done', active_job: :inline do
      expect_any_instance_of(AngryBatchTests::BatchCompletedJob).to receive(:perform).with('arg', arg2: '2') # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(AngryBatchTests::AlwaysComplete1Job).to receive(:perform) # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(AngryBatchTests::AlwaysComplete2Job).to receive(:perform).with('arg') # rubocop:disable RSpec/AnyInstance

      batch = described_class.new(label: 'test')
      batch.on_complete AngryBatchTests::BatchCompletedJob, 'arg', arg2: '2'
      batch.enqueue AngryBatchTests::AlwaysComplete1Job
      batch.enqueue AngryBatchTests::AlwaysComplete2Job, 'arg'
      batch.perform_later

      expect(batch.performed?).to eq true

      record = described_class::Batch.find_by! label: 'test'

      expect(record.state).to eq 'completed'
      expect(record.jobs.completed.count).to eq 2
    end

    it 'calls on failure job when a job is discarded', active_job: :inline do
      expect_any_instance_of(AngryBatchTests::BatchFailedJob).to receive(:perform) # rubocop:disable RSpec/AnyInstance

      batch = described_class.new(label: 'test')
      batch.on_failure AngryBatchTests::BatchFailedJob
      batch.enqueue AngryBatchTests::AlwaysFailJob
      batch.perform_later

      record = described_class::Batch.find_by! label: 'test'

      expect(record.state).to eq 'failed'
      expect(record.jobs.failed.count).to eq 1
      expect(record.jobs.first.error_message).to eq 'something went wrong'
    end
  end
end
