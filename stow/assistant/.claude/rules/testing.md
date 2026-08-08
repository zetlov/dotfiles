# Testing

- **TDD**: write the test first and see it fail (RED) → minimal implementation to pass (GREEN) → refactor. Use the tdd-guide agent for new features and bug fixes.
- **Coverage**: 80% minimum. Unit + integration tests always; E2E for critical user flows.
- **Failures**: check test isolation and mocks first; fix the implementation, not the test (unless the test itself is wrong).
- Always run tests locally before committing.
