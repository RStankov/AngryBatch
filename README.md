# AngryBatch

![Build Status](https://github.com/RStankov/AngryBatch/actions/workflows/main.yml/badge.svg)


**AngryBatch** is a lightweight batching utility for [ActiveJob](https://guides.rubyonrails.org/active_job_basics.html) that lets you group multiple jobs into a batch and trigger follow-up jobs when all jobs in the batch are done.

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

## Usage

```ruby
# Step 1: Allow the job to be batchable
class SomeJob
  include AngryBatch::Batchable
end

# Step 2: Create new batch queue
queue = AngryBatch.new(label: 'Debug label')

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
in the queue.perform_later
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
