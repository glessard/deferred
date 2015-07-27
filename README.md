# async & deferred
An alternative to NSOperation in Swift, based on closures.

`Deferred<T>` is useful in order to chain closures (blocks) together.

It is an approximation of module [Deferred](https://ocaml.janestreet.com/ocaml-core/111.25.00/doc/async_kernel/#Deferred) available in OCaml.

```
let d = Deferred {
  () -> Double in
  usleep(50000) // or a long calculation
  return 1.0
}
print(d.value)  // 1.0, after 50 milliseconds
```

A `Deferred` starts out with an undetermined value. It runs its closure in the background, and the return value of the closure will determine the `Deferred` at the time it completes.
A `Deferred` can schedule a block for execution once its value has been determined, using the `notify` method.
Computations can be chained by using `Deferred`'s `map`, `flatMap` and `apply` methods.

```
let transform = Deferred { Double(7*$0) }                     // Deferred<Int->Double>
let operand = Deferred { 6 }                                  // Deferred<Int>
let result = operand.apply(transform).map { $0.description }  // Deferred<String>
print(result.value)                                           // 42.0
```
The `value` property will block the current thread until it becomes determined. The rest of `Deferred` is implemented in a thread-safe and lock-free manner, relying largely on the properties of `dispatch_group_notify()`.

`Deferred` can run its closure on a specified `dispatch_queue_t` or concurrently at the requested `qos_class_t`, as can the `notify`, `map`, `flatMap` and `apply` methods. Otherwise it uses the global concurrent queue at the current qos class.

This repo started out as a set of wrappers over dispatch_async, so that
```
async { println("In the background") }
```
is equivalent to 
```
dispatch_async(dispatch_get_global_queue(qos_class_self(), 0), { println("In the background") })
```
