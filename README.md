# deferred [![Build Status](https://travis-ci.org/glessard/deferred.svg?branch=master)](https://travis-ci.org/glessard/deferred)
A library to help you transfer data, including eventual errors, between asynchronous blocks in Swift.
Deferred is fast and lock-free.

`Deferred<T>` allows you to chain closures together. A `Deferred` starts with an undetermined value. At some later time its value may become determined, after which the value can no longer change. Until the value becomes determined, computations that depend on it will be saved for future execution using a lock-free, thread-safe algorithm. The results of these computations are also represented by `Deferred` instances.  Thrown errors are propagated effortlessly along chains of `Deferred` instances.

`Deferred` started out as an approximation of OCaml's module [Deferred](https://ocaml.janestreet.com/ocaml-core/111.25.00/doc/async_kernel/#Deferred).

```
let d = Deferred<Double> {
  usleep(50000) // or a long calculation
  return 1.0
}
print(d.value!) // 1.0, after 50 milliseconds
```

A `Deferred` can schedule code that depends on its result for future execution using the `notify`,  `map`, `flatMap` and `apply` methods. Any number of such blocks can depend on the result of a `Deferred`. When an `Error` is thrown, it is propagated to all `Deferred`s that depend on it. A `recover` step can  be inserted in a chain of transforms in order to handle potential errors.

```
let transform = Deferred { i throws in Double(7*i) } // Deferred<Int throws -> Double>
let operand = Deferred(value: 6).delay(seconds: 0.1) // Deferred<Int>
let result = operand.apply(transform: transform)     // Deferred<Double>
print(result.value!)                                 // 42.0
```
The `result` property of `Deferred` (and its adjuncts, `value` , `error` and `get()`) will block the current thread until the `Deferred` becomes determined. The rest of `Deferred` is lock-free.

`Deferred` can run its closure on a specified `DispatchQueue`, or at the requested `DispatchQoS`. The `notify`, `map`, `flatMap`, `apply` and `recover` methods also have these options. By default, closures will be scheduled on a queue created at the current quality-of-service (qos) class.
