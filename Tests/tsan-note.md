#### Testing with the thread sanitizer

`Deferred` does not trigger Swift 5's runtime exclusivity checking, but it will trigger the thread sanitizer when running with the option `--sanitize=thread`.

The thread sanitizer does have an option to clean up its output, as documented [here](https://github.com/google/sanitizers/wiki/ThreadSanitizerSuppressions).

The test script (`Tests/test-script.sh`) already has the method baked in: run it with the option `--tsan`. In order to use output suppression in Xcode, add the `TSAN_OPTIONS` environment variable to your project's scheme. It must point to the path of the suppressions list, e.g.:
```
Name:  TSAN_OPTIONS
Value: suppressions="$(PROJECT_DIR)/../Tests/tsan-suppression"
```
The Xcode project included in this repository has the environment variable set in its `deferred` build scheme.
