# frozen_string_literal: true

require_relative 'angry_batch/version'
require_relative 'angry_batch/job'
require_relative 'angry_batch/batch'
require_relative 'angry_batch/handle'
require_relative 'angry_batch/batchable'
require_relative 'angry_batch/builder'
require_relative 'angry_batch/cleanup_cron_job'

module AngryBatch
  extend self

  def new(**)
    AngryBatch::Builder.new(**)
  end

  class BatchArgumentError < ArgumentError
  end
end

if defined?(Rails)
  require 'rails/engine'

  module AngryBatch
    class Engine < Rails::Engine
      # Engine configuration
    end
  end
end
