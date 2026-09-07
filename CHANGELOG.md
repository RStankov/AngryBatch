# Changelog

## Version 1.1.0 - 2026-09-05

- New migration — run `rails generate angry_batch:install` and `rails db:migrate` when upgrading
- Removed the `scheduling` state and the `AngryBatch::Batch.scheduling` scope; new batches start as `pending`
- Jobs and handlers can access their batch via `batch`
- Add jobs to a running batch with `batch.enqueue`
- Attach `metadata:` to a batch, readable via `batch.metadata`
- Track progress with `progress`, `pending_jobs_count`, `completed_jobs_count` and `failed_jobs_count`
- `perform_later` returns the `AngryBatch::Batch` record
- Jobs are enqueued after the surrounding transaction commits (Rails 7.2+)
- Bug fixes

## Version 1.0.1 - 2026-05-11

- Handle job failures via `after_discard` hook — marks job as `failed` and stores error message
- Bug fixes

## Version 1.0.0 - 2025-07-20

- Initial release
