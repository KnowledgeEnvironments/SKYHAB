# Contributing

Issues and pull requests are welcome. Please keep changes focused, document user-visible behavior,
and add tests proportional to risk.

Before submitting:

```sh
python3 tests/test_inventory.py .
python3 tests/test_presentation.py .
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
swift test --package-path macos
git diff --check
```

Do not submit real device captures, inventories, telemetry, screenshots, credentials, private
addresses, or location data. Reproduce adapter behavior with minimal fictional fixtures and RFC
5737 addresses. By contributing, you agree that your contribution is licensed under MIT.

For security vulnerabilities, follow `SECURITY.md` instead of opening a public issue.
