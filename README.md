# deferred
A library to help you transfer data, including errors, between asynchronous blocks in Swift; 
fast and lock-free. This could be used as a pure-Swift alternative to NSOperation.

`Deferred<T>` is useful in order to chain closures (blocks) together. A `Deferred` starts with an undetermined value. Until its value becomes ready, dependent computations will be saved for future execution using a lock-free, thread-safe algorithm. The results of these computations are also represented by `Deferred` instances.  Thrown errors are propagated effortlessly across threads.

`Deferred` is an approximation of module [Deferred](https://ocaml.janestreet.com/ocaml-core/111.25.00/doc/async_kernel/#Deferred) available in OCaml.

```
let d = Deferred {
  _ -> Double in
  usleep(50000) // or a long calculation
  return 1.0
}
print(d.value)  // 1.0, after 50 milliseconds
```

A `Deferred` can schedule code that depends on its result for future execution using the `notify`,  `map`, `flatMap` and `apply` methods. Any number of such blocks can depend on the result of a `Deferred`. When an `ErrorType` is thrown, it is propagated to all `Deferred`s that depend on it. A `recover` step can also be inserted in a chain of transforms in order to handle errors.

```
let transform = Deferred { i throws -> Double in Double(7*i) } // Deferred<Int throws -> Double>
let operand = Deferred(value: 6)                               // Deferred<Int>
let result = operand.apply(transform).map { $0.description }   // Deferred<String>
print(result.value)                                            // 42.0
```
The `result` property of `Deferred` (and its adjuncts, `value` and `error`) will block the current thread until the `Deferred` becomes determined. The rest of `Deferred` is lock-free.

`Deferred` can run its closure on a specified `dispatch_queue_t` or concurrently at the requested `qos_class_t`, as can the `notify`, `map`, `flatMap` and `apply` methods. By default closures will run on the global concurrent queue at the current quality-of-service (qos) class.

The simpler case of a wrapper over `dispatch_async` is handled by https://github.com/glessard/async.git
