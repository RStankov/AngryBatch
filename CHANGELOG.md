# Changelog

## Version 1.0.1 - 2026-05-10

- Handle job failures via `after_discard` hook — marks job as `failed` and stores error message
- Fix race condition in `check_status_of_jobs` — batch row is now locked during status check

## Version 1.0.0 - 2025-07-20

- Initial release
