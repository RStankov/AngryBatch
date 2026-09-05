# AngryBatch

![Build Status](https://github.com/RStankov/AngryBatch/actions/workflows/main.yml/badge.svg)
[![Gem Version](https://badge.fury.io/rb/angry_batch.svg)](http://badge.fury.io/rb/angry_batch)

**AngryBatch** is a batching utility for [ActiveJob](https://guides.rubyonrails.org/active_job_basics.html) that lets you group multiple jobs into a batch and trigger follow-up jobs when all jobs in the batch are done.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'angry_batch'
```

And then execute:

```
bundle
```

Or install it yourself as:

```
gem install angry_batch
```

Then, from your Rails app directory, create the angry tables:


```
rails generate angry_batch:install
rails db:migrate
```

### Upgrading from 1.0

Version 1.1 adds columns to the batches table. Run the generator again; it detects the existing install and only creates the upgrade migration:

```
rails generate angry_batch:install
rails db:migrate
```

The migration backfills the new counters from the existing job records. Jobs that finish on 1.0 code after the migration has run are not counted, so run the migration while your workers are stopped or drained, and restart them on 1.1 before enqueuing new batches.

## Usage

```ruby
# Step 1: Allow the job to be batchable
class SomeJob
  include AngryBatch::Batchable
end

# Step 2: Create new batch queue
queue = AngryBatch.new(label: 'Debug label', metadata: { account: account })

# Step 3: Add completion handler
#   `on_complete` job will be called when all other queue jobs have completed
#   (more than one handlers are supported)
queue.on_complete ToBeCalledWhenAllOtherJobsAreCompletedJob, argument

# Step 3.1: Add error handler
queue.on_failure HandleFailureJob, argument

# Step 4: Enqueue varios jobs
queue.enqueue SomeJob, argument1
queue.enqueue SomeJob, argument2
queue.enqueue SomeJob, argument3

# Step 5: Trigger all jobs in the queue
#   returns the AngryBatch::Batch record
batch = queue.perform_later
```

### Accessing the batch from a job

Every job that includes `AngryBatch::Batchable` can call `batch` while performing. It returns the `AngryBatch::Batch` record, or `nil` when the job was enqueued outside of a batch (or the batch record has already been cleaned up).

```ruby
class SomeJob < ApplicationJob
  include AngryBatch::Batchable

  def perform(argument)
    batch.label            # => 'Debug label'
    batch.metadata         # => { account: #<Account> }
    batch.progress         # => 33
  end
end
```

Completion and failure handlers get the same access when they include `AngryBatch::Batchable`. Handlers are not part of the batch, so including the module in them does not affect the batch counters.

```ruby
class ToBeCalledWhenAllOtherJobsAreCompletedJob < ApplicationJob
  include AngryBatch::Batchable

  def perform(argument)
    batch.metadata[:account]
  end
end
```

### Metadata

`metadata:` accepts a hash and is stored using ActiveJob argument serialization. Symbols, dates, nested hashes, and ActiveRecord models (via GlobalID) round-trip as-is. Values ActiveJob cannot serialize raise `ActiveJob::SerializationError` when the queue is created.

Metadata is read-only after the batch is created. If a model referenced in metadata is deleted before a job reads it, `batch.metadata` raises `ActiveJob::DeserializationError`, the same way job arguments do.

### Adding jobs from inside a job

A running job can add more jobs to its own batch. The batch does not complete until they finish, and jobs added this way can add jobs themselves.

```ruby
class ExportProjectJob < ApplicationJob
  include AngryBatch::Batchable

  def perform(project)
    project.files.find_each do |file|
      batch.enqueue ExportFileJob, file
    end
  end
end
```

`batch.enqueue` uses the same validation as the queue: the job must be an ActiveJob and include `AngryBatch::Batchable`. It can also be called on any pending `AngryBatch::Batch` record outside of a job.

Once a batch is completed or failed, `batch.enqueue` raises `AngryBatch::BatchFinishedError`. To run a second stage from a completion handler, create a new batch instead.

If a job raises after adding jobs, the added jobs still run. The batch ends `failed` once they are done, and the `on_failure` handlers run then. Note that a retried job (`retry_on`) runs `batch.enqueue` again and adds the jobs a second time.

If a job cannot be enqueued, whether a `before_enqueue` callback aborted it or your queue backend raised, the error is raised to the caller. A queue that cannot accept jobs is an infrastructure problem rather than a failed unit of work, so it belongs in your exception tracker and not in `on_failure`. The batch stays `pending` until you deal with it, and is reaped by `AngryBatch::CleanupCronJob` if you never do.

### Transactions

Jobs are pushed to your queue after the surrounding database transaction commits, so a worker never sees a job before its batch record exists. If the transaction rolls back, the batch and its jobs are discarded together and nothing is pushed. This applies to `perform_later` and to `batch.enqueue` alike.

```ruby
Account.transaction do
  account.update! exporting: true

  queue.perform_later # pushed once this transaction commits
end
```

On Rails 7.1 there is no hook for this and jobs are pushed immediately, so avoid enqueuing inside your own transaction there.

### Progress

Batches keep `jobs_count`, `completed_jobs_count`, and `failed_jobs_count` up to date as jobs finish. `pending_jobs_count` and `progress` (0 to 100) are derived from them.

The counters on a record are a snapshot. Call `batch.reload` to refresh them, for example after `batch.enqueue` on the same instance.

### Errors

A job is marked `failed` when ActiveJob discards it: `discard_on`, exhausted `retry_on`, or an unhandled exception. The batch is `failed` as soon as one job failed and every job has finished. A job only transitions once; a later successful run of a job already marked `failed` does not change it.

Prefer `retry_on` over adapter-level retries. With adapter-level retries (for example Sidekiq's own retry), the first unhandled exception marks the job `failed` even if a later attempt succeeds.

### Cleaning completed jobs

`AngryBatch` stores jobs in the database. You have to run `AngryBatch::CleanupCronJob` in a cron to clean the records.

```
AngryBatch::CleanupCronJob.perform
```

### Example

**Example 1**

```ruby
# You have a building with tenants.
# Every month, you must generate rent payments for them and notify them accordingly.

def generate_rent(building, period)
  queue = AngryBatch.new
  queue.on_complete GenerateBudgetSnapshotJob, building
  queue.on_complete NotifyBuildingOwnerJob, building

  building.tenants.each do |tenant|
    queue.enqueue GenerateTenantRentJob, tenant, period
  end

  queue.perform_later
end
```

**Example 2**

```ruby
# You have an account with many projects.
# For each project, you want to export its data individually.
# After all exports are done, you want to archive them into a zip file.

def export_account_information(account)
  queue = AngryBatch.new(label: "Export Projects for #{account.id}")
  queue.on_complete Export::ZipJob, account

  account.projects.find_each do |project|
    queue.enqueue Export::ProjectFilesJob, project
  end

  queue.perform_later
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Run the tests (`bundle exec rspec`)
6. Create new Pull Request

## Authors

* **Radoslav Stankov** - *creator* - [RStankov](https://github.com/RStankov)

## License

**[MIT License](./LICENSE.txt)**
