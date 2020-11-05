# Deferred [![Build Status](https://travis-ci.org/glessard/deferred.svg?branch=main)](https://travis-ci.org/glessard/deferred)
A lock-free, asynchronous `Result` for Swift 5 and up.

`Deferred<T>` allows you to chain computations together. A `Deferred` starts with an indeterminate, *unresolved* value. At some later time it may become *resolved*. Its value is then immutable for as long as that particular `Deferred` instance exists.
Until a `Deferred` becomes resolved, computations that depend on it can be saved for future execution using a lock-free, thread-safe algorithm. The results of these computations are also represented by `Deferred` instances. Errors thrown at any point in a `Deferred` context are propagated effortlessly.

`Deferred` started out as an approximation of OCaml's module [Deferred](https://ocaml.janestreet.com/ocaml-core/111.25.00/doc/async_kernel/#Deferred).

```
let d = Deferred<Double, Never> { // holds a `Double`, cannot hold an `Error`
  usleep(50000) // or a long calculation
  return 1.0
}
print(d.value!) // 1.0, after 50 milliseconds
```

A `Deferred` can schedule blocks of code that depend on its result for future execution using the `notify`,  `map`, and `flatMap` methods, among others. Any number of such blocks can depend on the result of a `Deferred`. When an `Error` is thrown, it is propagated to all `Deferred`s that depend on it. A `recover` step can  be inserted in a chain of transforms in order to handle potential errors.

```
let transform = Deferred<(Int) -> Double, Never> { i throws in Double(7*i) }
let operand = Deferred<Int, Error>(value: 6).delay(seconds: 0.1)
let result = operand.apply(transform: transform)                        // Deferred<Double, Error>
print(result.value!)                                                    // 42.0
```
The `result` property of `Deferred` (and its adjuncts, `value` , `error` and `get()`) will block the current thread until its `Deferred` becomes resolved. The rest of `Deferred` is lock-free.

`Deferred` can run its closure on a specified `DispatchQueue`, or at the requested `DispatchQoS`. The `notify`, `map`, `flatMap`, `apply` and `recover` methods also have these options. By default, closures will be scheduled on a queue created at the current quality-of-service (qos) class.


### Task execution scheduling

Tasks execute when a request exists. When creating a `Deferred` object, allocations are made, but no code is run immediately. When a code that depends on a `Deferred` requests the result, then the task is scheduled for execution. Requests are made by calling the `notify()`, `onValue()`, `onError()`, or `beginExecution()` methods (non-blocking); the `result`, `value` or `error` properties (blocking). Requests propagate up a chain of `Deferred`s.


### Long computations, cancellations and timeouts

Long background computations that support cancellation and timeout can be implemented easily by using the callback-style initializer for `Deferred<T>`. It takes a closure whose parameter is a `Resolver`. `Resolver` is associated with a specific instance of `Deferred`, and allows your code to be the data source of that `Deferred` instance. It also allows the data source to monitor the state of the `Deferred`.

    func bigComputation() -> Deferred<Double, Never>
    {
      return Deferred {
        resolver in
        DispatchQueue.global(qos: .utility).async {
          var progress = 0
          repeat {
            // first check that a result is still needed
            guard resolver.needsResolution else { return }
            // then work towards a partial computation
            Thread.sleep(until: Date() + 0.001)
            print(".", terminator: "")
            progress += 1
          } while progress < 20
          // we have an answer!
          resolver.resolve(value: .pi)
        }
      }
    }

    // let the child `Deferred` keep a reference to our big computation
    let timeout = 0.1
    let validated = bigComputation().validate(predicate: { $0 > 3.14159 && $0 < 3.14160 })
                                    .timeout(seconds: timeout, reason: String(timeout))

    do {
      print(validated.state)       // still waiting: no request yet
      let pi = try validated.get() // make the request and wait for value
      print(" ", pi)
    }
    catch Cancellation.timedOut(let message) {
      print()
      assert(message == String(timeout))
    }

In the above example, our computation closure works hard to compute the ratio of a circle's circumference to its diameter, then performs a rough validation of the output by comparing it with a known approximation. Note that the `Deferred` object performing the primary computation is not retained directly by this user code. When the timeout is triggered, the computation is correctly abandoned and the object is deallocated. General cancellation can be performed in a similar manner.

`Deferred` is carefully written to support cancellation by leveraging the Swift runtime's reference counting. In every case, when a new `Deferred` is returned by a function from the package, that returned reference is the only strong reference in existence. This allows cancellation to work properly for entire chains of computations, even if it is applied to the final link of the chain, regardless of error types.

### Using `Deferred` in a project

With the swift package manager, add the following to your package manifest's dependencies:

    .package(url: "https://github.com/glessard/deferred.git", from: "6.4.0")

To integrate in an Xcode 10 project, tools such as `Accio` and `xspm` are good options. The repository contains an Xcode 10 project with manually-assembled example iOS target. It requires some git submodules to be loaded using the command `git submodule update --init`.

#### License

This library is released under the MIT License. See LICENSE for details.
