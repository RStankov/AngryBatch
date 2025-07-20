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
        migration_template 'create_angry_batch_tables.rb', 'db/migrate/create_angry_batch_tables.rb'
      end
    end
  end
end
