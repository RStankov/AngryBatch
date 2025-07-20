# frozen_string_literal: true

FactoryBot.define do
  factory :angry_batch, class: 'AngryBatch::Batch' do
    state { 'pending' }
  end

  factory :angry_batch_job, class: 'AngryBatch::Job' do
    association :batch, factory: :angry_batch

    sequence(:active_job_idx) { "job-id-#{_1}" }

    state { 'pending' }

    active_job_class { 'FakeJob' }
  end
end
