# frozen_string_literal: true

require_relative 'lib/angry_batch/version'

Gem::Specification.new do |spec|
  spec.name = 'angry_batch'
  spec.version = AngryBatch::VERSION
  spec.authors = ['Radoslav Stankov']
  spec.email = ['rstankov@gmail.com']

  spec.summary = 'Lightweight ActiveJob batch processing with completion hooks'
  spec.description = 'AngryBatch allows you to group ActiveJobs into batches and define jobs to run once all batch jobs are completed.'
  spec.homepage = 'https://github.com/RStankov/angry-batch'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/RStankov/angry-batch'
  spec.metadata['changelog_uri'] = 'https://github.com/RStankov/angry-batch/blob/master/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w(git ls-files -z), chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w(bin/ test/ spec/ features/ .git .github appveyor Gemfile))
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r(\Aexe/)) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
end
