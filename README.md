# Deferred [![Build Status](https://travis-ci.org/glessard/deferred.svg?branch=master)](https://travis-ci.org/glessard/deferred)
A lock-free, asynchronous `Result` for Swift 4.2 and up.

`Deferred<T>` allows you to chain computations together. A `Deferred` starts with an indeterminate, *unresolved* value. At some later time it may become *resolved*. Its value is then immutable for as long as that particular `Deferred` instance exists.
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

Long background computations that support cancellation and timeout can be implemented easily by using the `TBD<T>` subclass of `Deferred<T>`. Its constructor takes a closure whose parameter is a `Resolver`. `Resolver` is associated with a specific instance of `Deferred`; it allows your code to be the data source of that `Deferred` instance, as well as to monitor its state.

    func bigComputation() -> Deferred<Double>
    {
      return TBD<Double> {
        resolver in
        DispatchQueue.global(qos: .utility).async {
          var progress = 0
          repeat {
            guard resolver.needsResolution else { return }
            Thread.sleep(until: Date() + 0.01) // work hard
            print(".", terminator: "")
            progress += 1
          } while progress < 20
          resolver.resolve(value: .pi)
        }
      }
    }

    let validated = bigComputation().validate(predicate: { $0 > 3.14159 && $0 < 3.14160 })
    let timeout = 0.1
    validated.timeout(seconds: timeout, reason: String(timeout))

    do {
      let pi = try validated.get()
      print(" ", pi)
    }
    catch DeferredError.timedOut(let message) {
      print()
      XCTAssertEqual(message, String(timeout))
    }

In the above example, our computation closure works hard to compute the ratio of a circle's circumference to its diameter, then performs a rough validation of the output by comparing it with a known approximation. Note that the `Deferred` object performing the primary computation is not retained directly by this user code. When the timeout is triggered, the computation is correctly abandoned and the object is deallocated. General cancellation can be performed in a similar manner.

`Deferred` is carefully written to support cancellation by leveraging reference counting. In every case, when a new `Deferred` is returned by a function from the package, that returned reference is the only strong reference in existence. This allows cancellation to work properly for entire chains of computations, even if it is applied to the final link of the chain.

### Using `Deferred` in a project

With the swift package manager, add the following to your package manifest's dependencies:

    .package(url: "https://github.com/glessard/deferred.git", from: "5.0.0")

To integrate in an Xcode project, tools such as `Accio` and `xspm` are good options. The repository contains a project with an example iOS target that is manually assembled. It requires some git submodules to be loaded using the command `git submodule update --init`.

#### License

This library is released under the MIT License. See LICENSE for details.
