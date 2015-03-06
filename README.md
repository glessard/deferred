# swiftian-dispatch
Lightweight, low-noise wrappers for libdispatch/GCD in Swift

Makes invoking Grand Central Dispatch more palatable by reducing the noise.
Does not introduce incompatibility with unnecessary new types.

```
async { println("In the background") }
```

is equivalent to 