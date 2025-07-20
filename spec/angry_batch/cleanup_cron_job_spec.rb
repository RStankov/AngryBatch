# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AngryBatch::CleanupCronJob do
  describe '#perform' do
    it 'destroys expired jobs' do
      expired = create(:angry_batch, state: 'completed', updated_at: 4.days.ago)
      not_expired = create(:angry_batch, state: 'completed', updated_at: 1.day.ago)

      described_class.perform_now

      expect_to_be_destroyed(expired)
      expect_not_to_be_destroyed(not_expired)
    end
  end
end
