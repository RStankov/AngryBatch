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

  class BatchCompletedJob < ActiveJob::Base
    def perform(_arg = nil, arg2: nil)
      # NOTE(rstankov): Do what ever
    end
  end
end

RSpec.describe AngryBatch do
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
  end
end
