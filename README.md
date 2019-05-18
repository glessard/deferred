# Deferred [![Build Status](https://travis-ci.org/glessard/deferred.svg?branch=master)](https://travis-ci.org/glessard/deferred)
An asynchronous `Result`, fast and lock-free.

`Deferred<T>` allows you to chain closures together. A `Deferred` starts with an indeterminate, *unresolved* value. At some later time it may become *resolved*. Its value is then immutable for as long as that particular `Deferred` instance exists.
Until a `Deferred` becomes resolved, computations that depend on it can be saved for future execution using a lock-free, thread-safe algorithm. The results of these computations are also represented by `Deferred` instances. Errors thrown at any point in a `Deferred` context are propagated effortlessly.

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
The `result` property of `Deferred` (and its adjuncts, `value` , `error` and `get()`) will block the current thread until its `Deferred` becomes resolved. The rest of `Deferred` is lock-free.

`Deferred` can run its closure on a specified `DispatchQueue`, or at the requested `DispatchQoS`. The `notify`, `map`, `flatMap`, `apply` and `recover` methods also have these options. By default, closures will be scheduled on a queue created at the current quality-of-service (qos) class.


### Long computations, cancellations and timeouts

Long background computations that support cancellation and timeout can be implemented easily by using the `TBD<T>` subclass of `Deferred<T>`. Its constructor takes a closure whose parameter is a `Resolver`. `Resolver` allows your code to monitor the state of the `Deferred` it's working to resolve, as well as (of course) resolve it.

    let bigComputation = TBD<Double> {
      resolver in
      DispatchQueue.global(qos: .utility).async {
        var progress = 1
        let start = Date()
        while true
        { // loop until we have the answer, checking from time to time
          // whether the answer is still needed.
          guard resolver.needsResolution else { break }

          Thread.sleep(until: start + Double(progress)*0.01) // work hard
          progress += 1
          if progress > 10
          {
            resolver.resolve(value: .pi)
            break
          }
        }
      }
    }

    let timeout = Bool.random() ? 0.1 : 1.0
    do {
      let pi = try bigComputation.timeout(seconds: timeout, reason: String(timeout)).get()
      assert(pi == .pi)
    }
    catch DeferredError.timedOut(let message) {
      assert(message == String(timeout))
    }

In the above example, the computation works hard to compute the ratio of a circle's circumference to its radius. A timeout is set randomly to either too short or long enough; 
