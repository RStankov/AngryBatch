# frozen_string_literal: true

require 'active_record'
require 'active_job'
require 'active_job/test_helper'
require 'factory_bot'
require 'rspec/rails/matchers/base_matcher'
require 'rspec/rails/matchers/active_job'

require 'angry_batch'

Dir.glob(File.expand_path('support/**/*.rb', __dir__)).each { |f| require f }

ENV['RAILS_ENV'] ||= 'test'

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger.level = Logger::WARN

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:',
)

ActiveRecord::Schema.define do
  create_table 'angry_batch_batches', force: :cascade do |t|
    t.string 'label'
    t.string 'state', default: 'scheduling', null: false
    t.integer 'jobs_count', default: 0, null: false
    t.json 'complete_handlers', default: [], null: false
    t.json 'failure_handlers', default: [], null: false
    t.datetime 'finished_at'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['state'], name: 'index_angry_batch_batches_on_state'
  end

  create_table 'angry_batch_jobs', force: :cascade do |t|
    t.bigint 'batch_id', null: false
    t.string 'state', default: 'pending', null: false
    t.string 'active_job_idx', null: false
    t.string 'active_job_class', null: false
    t.json 'active_job_arguments'
    t.string 'error_message'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
    t.index ['active_job_idx'], name: 'index_angry_batch_jobs_on_active_job_idx', unique: true
    t.index %w(batch_id state), name: 'index_angry_batch_jobs_on_batch_id_and_state'
  end

  add_foreign_key 'angry_batch_jobs', 'angry_batch_batches', column: 'batch_id'
end

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.include SpecSupport::Expectations
  config.include FactoryBot::Syntax::Methods
  config.include ActiveJob::TestHelper
  config.include RSpec::Rails::Matchers

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do |example|
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear

    if example.metadata[:active_job] == :inline
      ActiveJob::Base.queue_adapter.perform_enqueued_jobs    = true
      ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = true
    else
      ActiveJob::Base.queue_adapter.perform_enqueued_jobs    = false
      ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = false
    end
  end

  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
