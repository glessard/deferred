# swiftian-dispatch
An alternative to NSOperation in Swift, based on closures.

`Deferred<T>` is useful in order to chain closures (blocks) together.

It is an approximation of module [Deferred](https://ocaml.janestreet.com/ocaml-core/111.25.00/doc/async_kernel/#Deferred) available in OCaml.

```
let d1 = Deferred { 1.0 }           // Deferred<Double>
let d2 = d1.map { $0.description }  // Deferred<String>
println(d2.value)
```

A `Deferred` starts out with an undetermined value. It runs its closure in the background, and the return value of the closure will determine the `Deferred` at the time it completes.
A `Deferred` can schedule a block for execution once its value has been determined, using the `notify` method.
A `Deferred` can be transformed into another with `map`, `flatMap` and `apply` methods.

```
let transform = Deferred { i in Double(Int(arc4random()&0xff)*i) } // Deferred<Int->Double>
let operand = Deferred { Int(arc4random() & 0xff) }                // Deferred<Int>
let result = operand.apply(transform).map { $0.description }       // Deferred<String>
print(result.value)
```
The `value` property will block the current thread until it becomes determined. The rest of `Deferred` is implemented in a lock-free manner, relying largely on the properties of `dispatch_group_notify()`. It is thread-safe.

`Deferred` can run its closure on a specified `dispatch_queue_t` or at the requested `qos_class_t`, as can the `notify`, `map`, `flatMap` and `apply` methods. Otherwise it uses the global concurrent queue at the current qos class.
