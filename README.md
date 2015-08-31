# async & deferred
An alternative to NSOperation in Swift, based on closures.

`Deferred<T>` is useful in order to chain closures (blocks) together. A `Deferred` starts with an undetermined value. Until its value becomes ready, computations dependent on its value can saved for future execution using a lock-free, thread-safe algorithm. The results of these computations are also represented by other `Deferred` instances.

`Deferred` is an approximation of module [Deferred](https://ocaml.janestreet.com/ocaml-core/111.25.00/doc/async_kernel/#Deferred) available in OCaml.

```
let d = Deferred {
  _ -> Double in
  usleep(50000) // or a long calculation
  return 1.0
}
print(d.value)  // 1.0, after 50 milliseconds
```

A `Deferred` can schedule a block for execution once its value has been determined, using the `notify` method.
Computations can be chained by using `Deferred`'s `map`, `flatMap` and `apply` methods.

```
let transform = Deferred { i throws -> Double in Double(7*i) } // Deferred<Int throws -> Double>
let operand = Deferred(value: 6)                               // Deferred<Int>
let result = operand.apply(transform).map { $0.description }   // Deferred<String>
print(result.value)                                            // 42.0
```
The `result` property (and its adjuncts, `value` and `error`) will block the current thread until the `Deferred` becomes determined. The rest of `Deferred` is lock-free.

`Deferred` can run its closure on a specified `dispatch_queue_t` or concurrently at the requested `qos_class_t`, as can the `notify`, `map`, `flatMap` and `apply` methods. Otherwise it uses the global concurrent queue at the current qos class.

This repo started out as a set of wrappers over dispatch_async, so that
```
async { println("In the background") }
```
is equivalent to 
```
dispatch_async(dispatch_get_global_queue(qos_class_self(), 0), { println("In the background") })
```
