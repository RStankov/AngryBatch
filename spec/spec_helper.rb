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

ActiveRecord::Migration.verbose = false
migration_files = Dir[File.expand_path('../lib/generators/angry_batch/templates/*.rb', __dir__)]
migration_files.sort.each { |file| require file }

# Run the migrations
CreateAngryBatchTables.new.migrate(:up)

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
