# frozen_string_literal: true

require 'spec_helper'

module AngryBatchTests
  class RedularJob < ActiveJob::Base
  end

  class BatchableJob < ActiveJob::Base
    include AngryBatch::Batchable
  end

  class AbortsEnqueueBatchableJob < ActiveJob::Base
    include AngryBatch::Batchable

    before_enqueue { throw :abort }
  end
end

RSpec.describe AngryBatch::Builder do
  let(:batch) { described_class.new(label: 'Test') }

  describe '#enqueue' do
    it 'doesnt allow non ActiveJob classes' do
      expect { batch.enqueue String }.to raise_error(/must be a subclass of ActiveJob::Base/)
    end

    it 'doesnt allow non batchable job' do
      expect { batch.enqueue AngryBatchTests::RedularJob }.to raise_error(/must include AngryBatch::Batchable/)
    end

    it 'doesnt allow to be called after already performed' do
      batch.enqueue AngryBatchTests::BatchableJob

      batch.perform_later

      expect { batch.enqueue AngryBatchTests::BatchableJob }.to raise_error(/Batch is already running/)
    end
  end

  describe '#on_complete' do
    it 'doesnt allow non ActiveJob classes' do
      expect { batch.on_complete String }.to raise_error(/must be a subclass of ActiveJob::Base/)
    end

    it 'doesnt allow to be called after already performed' do
      batch.on_complete AngryBatchTests::RedularJob
      batch.enqueue AngryBatchTests::BatchableJob

      batch.perform_later

      expect { batch.on_complete AngryBatchTests::RedularJob }.to raise_error(/Batch is already running/)
    end

    it 'accepts multiple handlers' do
      batch.on_complete AngryBatchTests::RedularJob, '1', '2'
      batch.on_complete AngryBatchTests::RedularJob, '3', '4'
      batch.enqueue AngryBatchTests::BatchableJob

      batch.perform_later

      record = AngryBatch::Batch.find_by! label: 'Test'

      expect(record.complete_handlers).to eq [
        ['AngryBatchTests::RedularJob', %w(1 2)],
        ['AngryBatchTests::RedularJob', %w(3 4)],
      ]
    end
  end

  describe '#on_failure' do
    it 'doesnt allow non ActiveJob classes' do
      expect { batch.on_failure String }.to raise_error(/must be a subclass of ActiveJob::Base/)
    end

    it 'doesnt allow to be called after already performed' do
      batch.on_failure AngryBatchTests::RedularJob
      batch.enqueue AngryBatchTests::BatchableJob

      batch.perform_later

      expect { batch.on_failure AngryBatchTests::RedularJob }.to raise_error(/Batch is already running/)
    end

    it 'accepts multiple handlers' do
      batch.on_failure AngryBatchTests::RedularJob, '1', '2'
      batch.on_failure AngryBatchTests::RedularJob, '3', '4'
      batch.enqueue AngryBatchTests::BatchableJob

      batch.perform_later

      record = AngryBatch::Batch.find_by! label: 'Test'

      expect(record.failure_handlers).to eq [
        ['AngryBatchTests::RedularJob', %w(1 2)],
        ['AngryBatchTests::RedularJob', %w(3 4)],
      ]
    end
  end

  describe 'metadata' do
    it 'round-trips ActiveJob serializable values' do
      other_batch = create(:angry_batch)
      date = Date.new(2026, 9, 5)

      batch = described_class.new(label: 'Test', metadata: { mode: :full, nested: { 'count' => 1 }, date: date, record: other_batch })
      batch.enqueue AngryBatchTests::BatchableJob
      batch.perform_later

      record = AngryBatch::Batch.find_by! label: 'Test'

      expect(record.metadata).to eq(mode: :full, nested: { 'count' => 1 }, date: date, record: other_batch)
    end

    it 'defaults to an empty hash' do
      batch.enqueue AngryBatchTests::BatchableJob
      batch.perform_later

      expect(AngryBatch::Batch.find_by!(label: 'Test').metadata).to eq({})
    end

    it 'treats nil as an empty hash' do
      batch = described_class.new(label: 'Test', metadata: nil)
      batch.enqueue AngryBatchTests::BatchableJob
      batch.perform_later

      expect(AngryBatch::Batch.find_by!(label: 'Test').metadata).to eq({})
    end

    it 'raises for values ActiveJob cannot serialize' do
      expect { described_class.new(metadata: { callback: -> {} }) }.to raise_error(ActiveJob::SerializationError)
    end
  end

  describe '#perform_later' do
    it 'doesnt allow empty batches' do
      expect(batch.empty?).to eq true

      expect { batch.perform_later }.to raise_error(/Batch is empty/)
    end

    it 'doesnt to be called after already performed' do
      batch.enqueue AngryBatchTests::BatchableJob

      batch.perform_later

      expect(batch.performed?).to eq true

      expect { batch.perform_later }.to raise_error(/Batch is already running/)
    end

    it 'rolls back batch record if a job record fails to save' do
      batch.enqueue AngryBatchTests::BatchableJob

      allow_any_instance_of(AngryBatch::Job).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, 'forced failure') # rubocop:disable RSpec/AnyInstance

      expect { batch.perform_later }.to raise_error(ActiveRecord::StatementInvalid)

      expect(AngryBatch::Batch.find_by(label: 'Test')).to be_nil
      expect(AngryBatch::Job.count).to eq 0
    end

    it 'can be retried after a failed perform_later' do
      batch = described_class.new(label: 'Test', metadata: { mode: :full })
      batch.enqueue AngryBatchTests::BatchableJob

      call_count = 0
      allow_any_instance_of(AngryBatch::Job).to receive(:save!).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
        call_count += 1
        raise ActiveRecord::StatementInvalid, 'forced failure' if call_count == 1

        original.call(*args, **kwargs)
      end

      expect { batch.perform_later }.to raise_error(ActiveRecord::StatementInvalid)

      expect(batch.performed?).to eq false

      expect { batch.perform_later }.not_to raise_error

      expect(batch.performed?).to eq true
      expect(AngryBatch::Batch.find_by!(label: 'Test').metadata).to eq(mode: :full)
    end

    it 'returns the batch record' do
      batch.enqueue AngryBatchTests::BatchableJob

      result = batch.perform_later

      expect(result).to be_a AngryBatch::Batch
      expect(result).to be_persisted
      expect(result.label).to eq 'Test'
    end

    it 'raises on the first job that is not enqueued' do
      batch.enqueue AngryBatchTests::AbortsEnqueueBatchableJob
      batch.enqueue AngryBatchTests::BatchableJob

      expect { batch.perform_later }.to raise_error(ActiveJob::EnqueueError, /AbortsEnqueueBatchableJob/)

      expect(AngryBatchTests::BatchableJob).not_to have_been_enqueued
    end

    it 'does not settle a batch whose jobs all fail to enqueue' do
      batch.on_complete AngryBatchTests::RedularJob
      batch.enqueue AngryBatchTests::AbortsEnqueueBatchableJob

      expect { batch.perform_later }.to raise_error(ActiveJob::EnqueueError)

      record = AngryBatch::Batch.find_by! label: 'Test'

      expect(record.state).to eq 'pending'
      expect(AngryBatchTests::RedularJob).not_to have_been_enqueued
    end

    it 'creates batch and job records' do
      batch.enqueue AngryBatchTests::BatchableJob, 1, 2, 3
      batch.enqueue AngryBatchTests::BatchableJob, 4, 5, 6
      batch.enqueue AngryBatchTests::BatchableJob, 7, 8, 9

      batch.perform_later

      record = AngryBatch::Batch.find_by! label: 'Test'

      expect(record).to have_attributes(
        state: 'pending',
        jobs_count: 3,
      )

      job_records = record.jobs.order(id: :asc)

      expect(job_records[0]).to have_attributes(
        state: 'pending',
        active_job_idx: be_present,
        active_job_class: 'AngryBatchTests::BatchableJob',
        active_job_arguments: [1, 2, 3],
      )

      expect(job_records[1]).to have_attributes(
        state: 'pending',
        active_job_idx: be_present,
        active_job_class: 'AngryBatchTests::BatchableJob',
        active_job_arguments: [4, 5, 6],
      )

      expect(job_records[2]).to have_attributes(
        state: 'pending',
        active_job_idx: be_present,
        active_job_class: 'AngryBatchTests::BatchableJob',
        active_job_arguments: [7, 8, 9],
      )
    end
  end
end
