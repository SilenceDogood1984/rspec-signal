# Contributing

Thanks for helping. Bug reports and pull requests are welcome at
<https://github.com/SilenceDogood1984/rspec-signal>.

## Getting set up

```bash
git clone https://github.com/SilenceDogood1984/rspec-signal.git
cd rspec-signal
bin/setup
bundle exec rake     # specs + RuboCop
```

## Reporting a reduction bug

The most valuable bug report for this project is: *"rspec-signal removed something I
needed."*

Please include the raw backtrace, with `--backtrace` if RSpec was filtering it. A
new entry in `spec/fixtures/backtraces.rb` is the ideal shape for it — that is where
every reduction test gets its input, and a fixture that reproduces the problem makes
the fix straightforward.

## How the code is laid out

Almost everything is plain Ruby with no RSpec dependency:

```text
lib/rspec/signal/
  project.rb              which paths are first party, and how to render one
  backtrace/
    parser.rb             backtrace strings -> frames
    classifier.rb         frame -> project / library / framework
    reducer.rb            frames -> the ones worth keeping
  message.rb              failure text, plus its normalized form
  fingerprint.rb          the identity used for grouping
  grouper.rb              failures -> signatures
  reporters/              summary.md, signal.json, full.txt
  writer.rb               artifacts on disk
  redactor.rb             credential scrubbing

  failure_builder.rb      RSpec notification -> plain Failure   <- touches RSpec
  formatter.rb            the RSpec formatter                   <- touches RSpec
```

Only the last two know anything about RSpec. Keep it that way: it is what lets the
interesting logic be tested directly against fixtures.

## Standards for a change

- `bundle exec rake` passes.
- New behaviour has a test. Reduction changes need a fixture-driven one.
- If a change could increase output size, assert on the size. Several existing
  specs cap the number of rendered lines precisely so noise cannot creep back in.
- The formatter must never break someone's test run. Anything that touches
  `Formatter` or `FailureBuilder` should fail soft.

## Releasing

1. Update `lib/rspec/signal/version.rb` and `CHANGELOG.md`.
2. `bundle exec rake`
3. `bundle exec rake release`
