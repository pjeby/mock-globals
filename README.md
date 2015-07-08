# mock-globals

`mock-globals` lets you run test code in a simulated global environment, without affecting the *real* global environment, and without using a new `vm` context.  This lets you test code samples with clean state resets in between, and avoids the problem of test and library code using different `Object` or `Array` types (as would happen with multiple `vm` contexts).

**WARNING**: this is not a secure sandbox and is not intended for running untrusted code!  The "protection" it provides is only proof against *accidental* global modifications, and can be trivially bypassed in several ways that I can easily think of, and probably hundreds of less-trivial ways.  It is intended only for running tests, with *no thought given to any actual security*.

## Usage

```javascript
// Create a mock environment containing specified global variables
var Environment = require('mock-globals').Environment
var env = new Environment({someVar: "a value"})

// Evaluate code -- it will see the standard environment, but 
// with a mock console and any added variables
env.run("console.log(someVar)")

// Console output can be read using .getOutput()
assert(env.getOutput() === "a value\n")

// ...which resets to empty after being read
assert(env.getOutput() === "")

// And global variables are written to env.context
env.run("foo = 42; global.bar = 'baz'")
assert(env.context.foo === 42)
assert(env.context.bar === 'baz')

// ...instead of the real global context
assert(typeof foo === "undefined")
assert(!global.hasOwnProperty("bar"))
```

`run()` also accepts an optional second parameter, an object which can specify the following options:

* `filename` - the filename that the code will run as (and emit error traces as coming from)
* `printResults` - if true, the result of the `run()` will be written to the simulated console  (default value: true)
* `ignoreUndefined` - don't print an `undefined` result (default: true)
* `writer` - the function used to convert the result to a string suitable for writing (default value: the Node `repl` module's current `writer` property, which by default is a slight modified version of `util.inspect()`)

Last, but not least, the environment will include `module`, `exports`, and `require`, just like a real node module or `repl` environment.  (You can of course override any of these by changing the `.context` or passing them into the constructor, e.g. if you want a `require()` with a different base directory for module lookups.)

The default `module` object is actually a mock, whose `exports` property is delegated to the `exports` pseudo-global.  So if you change or pass in an `exports` global, the mock `module` object's `.exports` will automatically reflect that change.  Likewise, if running code sets `module.exports`, the `exports` global will be updated.


## How It Works

`Environment` objects have a `.context` property that contains all top-level variables that can be read or written by the code run with `.run()`.  It is an object whose prototype is the real `global` object, so any un-shadowed globals are visible to the running code.

The `.run()` method wraps the supplied code in a `with(MOCK_GLOBALS){}` block and makes other minor changes so that e.g. top-level function declarations don't write through to the global space.  It also pre-initializes the `.context` with undefined values for any new global variables assigned to by the code.

### Known Limitations

This process results in a near-perfect simulation of a private global environment...  except for the fact that it can easily be worked around if you know how it works.

It also:

* Doesn't isolate things like `process.domain`
* Works only in node.js, not the browser
* Temporarily creates a global variable called `MOCK_GLOBALS` during `.run()`
* Will create new `undefined` global variables when the code being `.run()` contains a global `var` statement.  (This is a side-effect of Javascript declaration hoisting; fortunately, it will not overwrite an *existing* global variable, or initialize such newly-created variables to anything but `undefined`.)

These are inherent limitations of this approach to mocking, so if they don't work for your use case, you'll need to use something else.