# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'stringio'
require 'rails/generators'
require 'generators/angry_batch/install_generator'

RSpec.describe AngryBatch::Generators::InstallGenerator do
  def run_generator(root)
    original = $stdout
    $stdout = StringIO.new

    described_class.start([], destination_root: root)
  ensure
    $stdout = original
  end

  def migrations(root)
    Dir.glob(File.join(root, 'db/migrate/*.rb')).map { |path| File.basename(path).sub(/\A\d+_/, '') }
  end

  def install_previous_version(root)
    FileUtils.mkdir_p File.join(root, 'db/migrate')
    FileUtils.cp 'spec/fixtures/create_angry_batch_tables_v1_0.rb', File.join(root, 'db/migrate/20250101000000_create_angry_batch_tables.rb')
  end

  it 'creates the table migration on a fresh install' do
    Dir.mktmpdir do |root|
      run_generator(root)

      expect(migrations(root)).to eq %w(create_angry_batch_tables.rb)
    end
  end

  it 'creates the upgrade migration when a 1.0 table migration exists' do
    Dir.mktmpdir do |root|
      install_previous_version(root)

      run_generator(root)

      expect(migrations(root)).to contain_exactly('create_angry_batch_tables.rb', 'add_metadata_and_counters_to_angry_batch_tables.rb')
    end
  end

  it 'creates nothing when the table migration is already up to date' do
    Dir.mktmpdir do |root|
      run_generator(root)

      expect { run_generator(root) }.not_to change { migrations(root) }
    end
  end
end
