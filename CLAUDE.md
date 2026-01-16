# Claude Code Instructions

## Environment Setup

1. Install the correct bundler version:
```bash
gem install bundler -v 2.5.18
```

2. Install dependencies:
```bash
bundle install
```

## Running Tests

Always use `bundle exec rspec` to run the test suite:

```bash
bundle exec rspec
```

For specific test files:

```bash
bundle exec rspec spec/some_spec.rb
```
