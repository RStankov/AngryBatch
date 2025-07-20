# frozen_string_literal: true

require 'spec_helper'

module AngryBatchTests
  class RedularJob < ActiveJob::Base
  end

  class BatchableJob < ActiveJob::Base
    include AngryBatch::Batchable
  end
end

RSpec.describe AngryBatch::Builder do
  let(:batch) { described_class.new(label: 'Test') }

  describe '#enqueue' do
    it 'doesnt allow non ActiveJob classes' do
      expect { batch.enqueue String }.to raise_error(/be a subclass of ActiveJob::Base/)
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
      expect { batch.on_complete String }.to raise_error(/be a subclass of ActiveJob::Base/)
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
      expect { batch.on_failure String }.to raise_error(/be a subclass of ActiveJob::Base/)
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
