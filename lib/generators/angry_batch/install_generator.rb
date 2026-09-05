# frozen_string_literal: true

module AngryBatch
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      def self.next_migration_number(_dirname)
        Time.now.utc.strftime('%Y%m%d%H%M%S')
      end

      def copy_migrations
        existing = self.class.migration_exists?(File.join(destination_root, 'db/migrate'), 'create_angry_batch_tables')

        if existing.nil?
          migration_template 'create_angry_batch_tables.rb', 'db/migrate/create_angry_batch_tables.rb'
          return
        end

        return if File.read(existing).include?('completed_jobs_count')

        migration_template 'add_metadata_and_counters_to_angry_batch_tables.rb', 'db/migrate/add_metadata_and_counters_to_angry_batch_tables.rb', skip: true
      end
    end
  end
end
