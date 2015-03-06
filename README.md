# swiftian-dispatch
Lightweight, low-noise wrappers for libdispatch/GCD in Swift

Increases the readability of Grand Central Dispatch in Swift by reducing the noise.
Does not introduce incompatibility by unnecessarily introducing new wrapper types. You create and obtain queues the same way, you create dispatch groups the same way, you can use dispatch_{sg}et_context() the same way.

```
async { println("In the background") }
```
is equivalent to 
```
dispatch_async(dispatch_get_global_queue(qos_class_self(), 0), { println("In the background") })
```

`async` has versions that can take a dispatch_queue_t or a qos_class_t, and optionally a dispatch_group_t.

`Result<T>` is a new generic type; it's useful in order to chain blocks together.

```
let result1 = async { 1.0 }                     // Result<Double>
let result2 = result1.notify { $0.description } // Result<String>
println(result2.get())
```

The `notify` methods on Result have the same possible parameters as the `async` functions.

For good measure, similar `async` and `notify` methods were added as extensions on `dispatch_group_t`, in addition to `wait`

```
let g = dispatch_group_create()
async(group: g) { sleep(2.0) }
if g.wait(forSeconds: 1.0) != 0
{
  g.wait()
}
```
