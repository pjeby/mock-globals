# Mock Global Execution Environment

### Environment Objects

An environment is like a stripped-down node REPL that runs code samples in
a private `.context` that retains its state and records its console output.
The context inherits from the Node global environment, and sees any changes
to globals that aren't shadowed by assignments in the code samples (or in the
initially-provided globals).

    class exports.Environment

        repl = require 'repl'
        Console = require('console').Console

        constructor: (globals={}) ->
            @outputStream = Object.assign [],
                write: (data) -> @push(data); this
                once: -> this
                removeListener: -> this
                listenerCount: -> 0

            @context = ctx = Object.create(global)
            assign(ctx,
                console: new Console(@outputStream)
                global: ctx
                GLOBAL: ctx
                THIS: ctx       # Used for rewrites of top-level `this`
                module: @dummyModule()
                exports: {}
                require: require
            )
            assign(ctx, globals)

For the exposed `module`, we use a clone of the mock-globals module, with an
`exports` property that gets/sets the context `exports`, so that code samples
can run in an environment that closely resembles a standard module.

        dummyModule: ->
            return Object.create(module, exports: {
                get: => @context.exports
                set: (v) => @context.exports = v
                enumerable: yes
            })

#### Code Rewriting

Before they can be run, code samples are wrapped in a `with(MOCK_GLOBALS)`
block, so that variables are read and written from the Environment's `.context`
instead of from the process globals.  In order for this to work, the context
must have properties for every global variable assignment or function
declaration in the code sample, and function declarations must be converted to
variable assignments.  (Otherwise, they'll write directly to global context.)

So, we use the `recast` module to scan the code and track what global variables
are assigned to, along with the location of any function declarations.  Any
such variables are added as `undefined` properties of the context

        recast = require 'recast'

        rewrite: (src) ->

            context = @context
            funcs = []

            recast.visit recast.parse(src),
                visitAssignmentExpression: vae = (p) ->
                    @traverse(p)
                    target = p.node.left
                    if target.type is 'VariableDeclaration'
                        target = target.declarations[0].id
                    name = target.name
                    return if name of context
                    s = p.scope.lookup(target.name)
                    if not s? or s.isGlobal
                        context[name] = undefined
                    return
                visitForInStatement: vae

                visitFunctionDeclaration: (p) ->
                    s = p.scope.lookup(name = p.node.id.name)
                    if not s? or s.isGlobal
                        funcs.push [name, p.node.loc]
                        context[name] = undefined unless name of context
                    @traverse(p); return

In addition to variables and functions, it's also possible to refer to the
global context as `this`, so we replace global-scope `this` with `THIS`, which
avoids changing any code positions, but will now refer to the running context
instead of the global context.

                visitThisExpression: (p) ->
                    @traverse(p)
                    if p.scope.isGlobal
                        {line, column} = p.node.loc.start
                        src = replaceAt(src, line, column, 'this', 'THIS')

In order to avoid reformatting the source code any more than necessary, we
don't use recast's source printer.  Instead, if there are any changes
necessary, we splice the assignment directly into the code at the exact
locations where the functions were declared.  We do this in reverse order
(popping locations off the list) so that if there are multiple declarations on
the same line, the column positions of earlier declarations will remain valid.

(We also have to make sure that these assignment statements end with a `;`, but
we remove the extra `;` we add if it's a duplicate.)

            if funcs.length
                while funcs.length
                    [name, loc] = funcs.pop()
                    {line, column:col} = loc.end
                    src = replaceAt(src, line, col, '', ';')
                    src = replaceAt(src, line, col, ';;', ';')
                    {line, column:col} = loc.start
                    src = replaceAt(src, line, col, '', name + '=')

            return "with(MOCK_GLOBALS){#{src}\n}"

The actual source code replacement is done with a parameterized regular
expression that handles counting lines and columns.

        replaceAt = (TEXT, ROW, COL, MATCH, REPLACE) ->
            match = ///^
                ((?:[^\n]*\n){#{ROW-1}}.{#{COL}})#{MATCH}([\s\S]*)
            $///.exec(TEXT)
            if match then match[1] + REPLACE + match[2] else TEXT

#### Running Code

In principle, running a code sample is as simple as creating a `vm.Script` and
running it.  But in practice, node 0.12 and up expect an options object rather
than a filename, so if the supplied options contain a filename, we have to
figure out whether we're running on something newer than that, by checking for
the existence of `vm.runInDebugContext()` (which was added in 0.12).

        vm = require 'vm'

        toScript = (code, filename, displayErrors=no) ->
            if filename then new vm.Script(code,
                if vm.runInDebugContext?    # new API
                    {filename, displayErrors}
                else filename
            )
            else new vm.Script(code)

To avoid mixing `recast()` syntax errors with Node syntax errors, we create
a dummy script for the unmodified code sample before creating the rewritten
script we'll actually run.  We then wrap the script execution with a temporary
global assignment to `MOCK_GLOBALS`, so the `with()` statement will pick up
our context when it executes.  (It's not needed after that.)

        run: (code, opts={}) ->
            toScript(code, opts.filename, yes) # force syntax error here
            script = toScript(@rewrite(code), opts.filename)

            current_global = global
            current_global.MOCK_GLOBALS = @context
            try
                res = script.runInThisContext(displayErrors: false)
            finally
                delete current_global.MOCK_GLOBALS

Once the result of running the script is obtained, it's written to the console,
unless it's been disabled by setting the options' `.printResults` to false.
(Undefined values aren't printed, though, unless the `.ignoreUndefined'` option
has been set to false.)  In any event, the current `repl.writer` is used to
format the output, unless it's overridden via the `.writer` option.

            if opts.printResults ? true
                unless res is undefined and (opts.ignoreUndefined ? true)
                    @outputStream.write (opts.writer ? repl.writer)(res)+'\n'
            return res


#### Console Output Tracking

Last, but not least, the `.getOutput()` method just returns the current
accumulated output and resets it to accumulate from empty again.

        getOutput: -> @outputStream.splice(0).join ''


#### `assign()`

The `assign()` function is roughly equivalent to an `Object.assign()` polyfill,
except that it uses `Object.defineProperty()` to ensure that e.g. an inherited
descriptor on the target can't veto an assignment.  (As can happen when
assigning to an object that inherits from the global context, as with the
`.context` property of an `Environment`.)

    assign = (target={}) ->
        to = Object(target)
        writable = configurable = enumerable = yes
        for arg, i in arguments when i and arg?     # skip first and empties
            arg = Object(arg)
            for k in Object.keys(arg)
                Object.defineProperty(to, k, {
                    value: arg[k], writable, configurable, enumerable
                })
        return to









