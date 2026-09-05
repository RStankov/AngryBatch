# frozen_string_literal: true

require 'spec_helper'

module AngryBatchTests
  class SerializableJob < ActiveJob::Base
    include AngryBatch::Batchable
  end
end

RSpec.describe AngryBatch::Batchable do
  describe '#serialize' do
    it 'carries the batch id through ActiveJob deserialization' do
      job = AngryBatchTests::SerializableJob.new('arg')
      job.angry_batch_id = 42

      restored = ActiveJob::Base.deserialize(job.serialize)

      expect(restored).to be_a AngryBatchTests::SerializableJob
      expect(restored.angry_batch_id).to eq 42
    end
  end

  describe '#batch' do
    it 'returns the batch record' do
      batch = create(:angry_batch)

      job = AngryBatchTests::SerializableJob.new
      job.angry_batch_id = batch.id

      expect(job.batch).to eq batch
    end

    it 'returns nil when enqueued outside of a batch' do
      job = AngryBatchTests::SerializableJob.new

      expect(job.batch).to be_nil
    end

    it 'returns nil when the batch record no longer exists' do
      job = AngryBatchTests::SerializableJob.new
      job.angry_batch_id = -1

      expect(job.batch).to be_nil
    end
  end
end
