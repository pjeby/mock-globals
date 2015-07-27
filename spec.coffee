{expect, should} = chai = require 'chai'
should = should()
chai.use require 'sinon-chai'

{spy} = sinon = require 'sinon'

spy.named = (name, args...) ->
    s = if this is spy then spy(args...) else this
    s.displayName = name
    return s

{Environment} = require './'

# Node vm module got script options as of 0.11.7, but our detection
# approach doesn't kick in until 0.11.14

is10 = require('semver').lt(process.version, '0.11.14')
























describe "Environment(globals)", ->

    beforeEach -> @env = new Environment(x:1, y:2)

    describe ".run(code, opts)", ->

        it "returns the result", ->
            expect(@env.run('1')).to.equal(1)

        it "throws any syntax errors", ->
            expect(=> @env.run('if;', filename:'foo.js')).to.throw(SyntaxError,
                "#{if is10 then '' else 'foo.js:1\nif;\n  ^\n' \
                }Unexpected token ;")

        it "throws any runtime errors", ->
            expect(=> @env.run('throw new TypeError')).to.throw(
               TypeError
            )

        it "sets the filename from opts.filename", ->
            try
                @env.run('throw new Error', filename: 'foobar.js')
            catch e
                expect(e.stack).to.match /at foobar.js:1/

        it "uses the same Javascript engine", ->
            expect(@env.run('[]')).to.be.instanceOf Array
            expect(@env.run('({})')).to.be.instanceOf Object
            expect(@env.run('(function(){})')).to.be.instanceOf Function
            expect(@env.run('new Error')).to.be.instanceOf Error

        describe "shadows globals", ->

            it "in loose mode", ->
                expect(@env.run('console')).to.equal(@env.context.console)

            it "in strict mode", ->
                expect(
                    @env.run('(function(){"use strict"; return console})()')
                ).to.equal(@env.context.console)

        describe "prevents global assignment via", ->

            check = (title, code, result, strict=yes) -> it title, ->
                expect(@env.run(code)).to.equal(result)
                if strict
                    expect(global.hasOwnProperty("foo#{result}")).to.be.false
                else
                    expect(typeof global["foo#{result}"]).to.equal 'undefined'

            check "simple assignment", 'foo1=1', 1
            check "var declaration", 'var q, foo2=2; foo2', 2, false
            check "nested assignment", 'function q(){ return foo3=3;}; q()', 3

            check "function declaration",
                'function foo4() { return 4; }; foo4()', 4

            check "conditional declaration",
                'if (1) function foo5() { return 5; }; foo5()', 5

            check "strict mode assignment",
                'function x() { "use strict"; foo6=6; }; x(); foo6', 6

            check "global.property assignment",
                'global.foo7 = 7; foo7', 7

            check "`this` assignment", 'this.foo8 = 8; foo8', 8

            check "for loops", 'for (foo9=0; foo9<9; foo9++) {}; foo9', 9

            check "for-var loops",
                'for (var foo10=0; foo10<10; foo10++) {}; foo10', 10, false

            check "for-in loops", 'for (fooX in {X:1}) {}; fooX', 'X'

            check "for var-in loops",
                'for (var fooY in {Y:1}) {}; fooY', 'Y', false





    describe ".context variables", ->

        it "include the globals used to create the environment", ->
            expect(@env.context.x).to.equal(1)
            expect(@env.context.y).to.equal(2)

        it "are readable by run() code", ->
            expect(@env.run('[x,y]')).to.eql([1,2])

        it "are writable by run() code", ->
            @env.run('var x=3; y=4')
            expect(@env.context.x).to.equal(3)
            expect(@env.context.y).to.equal(4)

        it "can be defined by run() code", ->
            @env.run('var z=42')
            expect(@env.context.z).to.equal(42)

        it "include a global and GLOBAL that map to the context", ->
            expect(@env.run('global')).to.equal(@env.context)
            expect(@env.run('GLOBAL')).to.equal(@env.context)

        it "include a complete `require()` implementation", ->
            req = @env.context.require
            expect(req('./spec.coffee')).to.equal(exports)
            expect(req.cache).to.equal(require.cache)
            expect(req.resolve('./spec.coffee')).to.equal(
                   require.resolve('./spec.coffee'))

        it "include a unique (but linked) exports and module.exports", ->
            e1 = @env;  e2 = new Environment()
            expect(c1 = e1.context).to.not.equal(c2 = e2.context)
            expect(m1 = c1.module) .to.not.equal(m2 = c2.module)
            expect(x1 = m1.exports).to.not.equal(x2 = m2.exports)
            expect(x1).to.exist.and.equal(c1.exports).and.deep.equal({})
            expect(x2).to.exist.and.equal(c2.exports).and.deep.equal({})
            nx1 = c1.exports = {}
            expect(m1.exports).to.equal(c1.exports).and.equal(nx1)
            nx2 = m2.exports = {}
            expect(m2.exports).to.equal(c2.exports).and.equal(nx2)

    describe ".getOutput()", ->

        beforeEach -> @console = @env.context.console

        it "returns all log/dir/warn/error text from .context.console", ->
            @console.error("w")
            @console.warn("x")
            @console.log("y")
            @console.dir("z")
            expect(@env.getOutput().split('\n')).to.eql(
                ['w','x','y',"'z'", ""]
            )
        it "resets after each call", ->
            @console.log("x")
            expect(@env.getOutput().split('\n')).to.eql(['x',''])
            expect(@env.getOutput()).to.eql('')


    describe "result logging", ->

        it "logs results other than undefined", ->
            @env.run('1')
            @env.run('null')
            @env.run('if(0) 1;')
            expect(@env.getOutput()).to.eql('1\nnull\n')

        it "logs undefined if opts.ignoreUndefined is false", ->
            @env.run('if(0) 1;', ignoreUndefined: no)
            expect(@env.getOutput()).to.eql('undefined\n')

        it "uses opts.writer if specified", ->
            @env.run('2', writer: writer = spy.named 'writer', -> 'hoohah!')
            expect(@env.getOutput()).to.eql('hoohah!\n')
            expect(writer).to.have.been.calledOnce
            expect(writer).to.have.been.calledWithExactly(2)

        it "doesn't log results if disabled", ->
            @env.run('1', printResults: no)
            expect(@env.getOutput()).to.eql('')


    describe ".rewrite(code)", ->

        it "doesn't rewrite inner `this`", ->
            expect(@env.rewrite(src = '(function(){this})'))
            .to.equal("with(MOCK_GLOBALS){#{src}}")

        describe "handles oddly formatted stuff like", ->
            it "tabs messing up offset positions"
            it "carriage returns and other zero-space characters"
            it "wide character offsets"































