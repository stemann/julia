# This file is a part of Julia. License is MIT: https://julialang.org/license

using Test
using Distributed
using Dates
if !Sys.iswindows() && isa(stdin, Base.TTY)
    import REPL
end
using Printf: @sprintf
using Base: Experimental

include("choosetests.jl")
include("testenv.jl")
include("buildkitetestjson.jl")

(; tests, net_on, exit_on_error, use_revise, buildroot, seed) = choosetests(ARGS)
tests = unique(tests)

if Sys.islinux()
    const SYS_rrcall_check_presence = 1008
    global running_under_rr() = 0 == ccall(:syscall, Int,
        (Int, Int, Int, Int, Int, Int, Int),
        SYS_rrcall_check_presence, 0, 0, 0, 0, 0, 0)
else
    global running_under_rr() = false
end

if use_revise
    # First put this at the top of the DEPOT PATH to install revise if necessary.
    # Once it's loaded, we swizzle it to the end, to avoid confusing any tests.
    pushfirst!(DEPOT_PATH, joinpath(buildroot, "deps", "jlutilities", "depot"))
    using Pkg
    Pkg.activate(joinpath(@__DIR__, "..", "deps", "jlutilities", "revise"))
    Pkg.instantiate()
    using Revise
    union!(Revise.stdlib_names, Symbol.(STDLIBS))
    push!(DEPOT_PATH, popfirst!(DEPOT_PATH))
    # Remote-eval the following to initialize Revise in workers
    const revise_init_expr = quote
        using Revise
        const STDLIBS = $STDLIBS
        union!(Revise.stdlib_names, Symbol.(STDLIBS))
        revise_trackall()
    end
end

if isempty(tests)
    println("No tests selected. Exiting.")
    exit()
end

const max_worker_rss = if haskey(ENV, "JULIA_TEST_MAXRSS_MB")
    parse(Int, ENV["JULIA_TEST_MAXRSS_MB"]) * 2^20
else
    typemax(Csize_t)
end
limited_worker_rss = max_worker_rss != typemax(Csize_t)

# Check all test files exist
isfiles = isfile.(test_path.(tests) .* ".jl")
if !all(isfiles)
    error("did not find test files for the following tests: ",
          join(tests[.!(isfiles)], ", "))
end

const node1_tests = String[]
function move_to_node1(t)
    if t in tests
        splice!(tests, findfirst(isequal(t), tests))
        push!(node1_tests, t)
    end
    nothing
end

# Base.compilecache only works from node 1, so precompile test is handled specially
move_to_node1("ccall")
move_to_node1("precompile")
move_to_node1("SharedArrays")
move_to_node1("threads")
move_to_node1("Distributed")
move_to_node1("gc")
# Ensure things like consuming all kernel pipe memory doesn't interfere with other tests
move_to_node1("stress")

# In a constrained memory environment, run the "distributed" test after all other tests
# since it starts a lot of workers and can easily exceed the maximum memory
limited_worker_rss && move_to_node1("Distributed")

# Move LinearAlgebra and Pkg tests to the front, because they take a while, so we might
# as well get them all started early.
for prependme in ["LinearAlgebra", "Pkg"]
    prependme_test_ids = findall(x->occursin(prependme, x), tests)
    prependme_tests = tests[prependme_test_ids]
    deleteat!(tests, prependme_test_ids)
    prepend!(tests, prependme_tests)
end

import LinearAlgebra
cd(@__DIR__) do
    # `net_on` implies that we have access to the loopback interface which is
    # necessary for Distributed multi-processing. There are some test
    # environments that do not allow access to loopback, so we must disable
    # addprocs when `net_on` is false. Note that there exist build environments,
    # including Nix, where `net_on` is false but we still have access to the
    # loopback interface. It would be great to make this check more specific to
    # identify those situations somehow. See
    #   * https://github.com/JuliaLang/julia/issues/6722
    #   * https://github.com/JuliaLang/julia/pull/29384
    #   * https://github.com/JuliaLang/julia/pull/40348
    n = 1
    JULIA_TEST_USE_MULTIPLE_WORKERS = Base.get_bool_env("JULIA_TEST_USE_MULTIPLE_WORKERS", false)
    # If the `JULIA_TEST_USE_MULTIPLE_WORKERS` environment variable is set to `true`, we use
    # multiple worker processes regardless of the value of `net_on`.
    # Otherwise, we use multiple worker processes if and only if `net_on` is true.
    if net_on || JULIA_TEST_USE_MULTIPLE_WORKERS
        n = min(Sys.CPU_THREADS, length(tests))
        n > 1 && addprocs_with_testenv(n)
        LinearAlgebra.BLAS.set_num_threads(1)
    end
    skipped = 0

    @everywhere include("testdefs.jl")

    if use_revise
        @invokelatest revise_trackall()
        Distributed.remotecall_eval(Main, workers(), revise_init_expr)
    end

    println("""
        Running parallel tests with:
          getpid() = $(getpid())
          nworkers() = $(nworkers())
          nthreads(:interactive) = $(Threads.threadpoolsize(:interactive))
          nthreads(:default) = $(Threads.threadpoolsize(:default))
          Sys.CPU_THREADS = $(Sys.CPU_THREADS)
          Sys.total_memory() = $(Base.format_bytes(Sys.total_memory()))
          Sys.free_memory() = $(Base.format_bytes(Sys.free_memory()))
          Sys.uptime() = $(Sys.uptime()) ($(round(Sys.uptime() / (60 * 60), digits=1)) hours)
        """)

    #pretty print the information about gc and mem usage
    testgroupheader = "Test"
    workerheader = "(Worker)"
    name_align    = maximum([textwidth(testgroupheader) + textwidth(" ") + textwidth(workerheader); map(x -> textwidth(x) + 3 + ndigits(nworkers()), tests)])
    elapsed_align = textwidth("Time (s)")
    gc_align      = textwidth("GC (s)")
    percent_align = textwidth("GC %")
    alloc_align   = textwidth("Alloc (MB)")
    rss_align     = textwidth("RSS (MB)")
    printstyled(testgroupheader, color=:white)
    printstyled(lpad(workerheader, name_align - textwidth(testgroupheader) + 1), " | ", color=:white)
    printstyled("Time (s) | GC (s) | GC % | Alloc (MB) | RSS (MB)\n", color=:white)
    results = []
    print_lock = stdout isa Base.LibuvStream ? stdout.lock : ReentrantLock()
    if stderr isa Base.LibuvStream
        stderr.lock = print_lock
    end

    function print_testworker_stats(test, wrkr, resp)
        @nospecialize resp
        lock(print_lock)
        try
            printstyled(test, color=:white)
            printstyled(lpad("($wrkr)", name_align - textwidth(test) + 1, " "), " | ", color=:white)
            time_str = @sprintf("%7.2f",resp[2])
            printstyled(lpad(time_str, elapsed_align, " "), " | ", color=:white)
            gc_str = @sprintf("%5.2f", resp[5].total_time / 10^9)
            printstyled(lpad(gc_str, gc_align, " "), " | ", color=:white)

            # since there may be quite a few digits in the percentage,
            # the left-padding here is less to make sure everything fits
            percent_str = @sprintf("%4.1f", 100 * resp[5].total_time / (10^9 * resp[2]))
            printstyled(lpad(percent_str, percent_align, " "), " | ", color=:white)
            alloc_str = @sprintf("%5.2f", resp[3] / 2^20)
            printstyled(lpad(alloc_str, alloc_align, " "), " | ", color=:white)
            rss_str = @sprintf("%5.2f", resp[6] / 2^20)
            printstyled(lpad(rss_str, rss_align, " "), "\n", color=:white)
        finally
            unlock(print_lock)
        end
        nothing
    end

    global print_testworker_started = (name, wrkr)->begin
        pid = running_under_rr() ? remotecall_fetch(getpid, wrkr) : 0
        at = lpad("($wrkr)", name_align - textwidth(name) + 1, " ")
        lock(print_lock)
        try
            printstyled(name, at, " |", " "^elapsed_align,
                    "started at $(now())",
                    (pid > 0 ? " on pid $pid" : ""),
                    "\n", color=:white)
        finally
            unlock(print_lock)
        end
        nothing
    end

    function print_testworker_errored(name, wrkr, @nospecialize(e))
        lock(print_lock)
        try
            printstyled(name, color=:red)
            printstyled(lpad("($wrkr)", name_align - textwidth(name) + 1, " "), " |",
                " "^elapsed_align, " failed at $(now())\n", color=:red)
            if isa(e, Test.TestSetException)
                for t in e.errors_and_fails
                    show(t)
                    println()
                end
            elseif e !== nothing
                Base.showerror(stdout, e)
            end
            println()
        finally
            unlock(print_lock)
        end
    end


    all_tests = [tests; node1_tests]

    local stdin_monitor
    all_tasks = Task[]
    o_ts_duration = 0.0
    try
        # Monitor stdin and kill this task on ^C
        # but don't do this on Windows, because it may deadlock in the kernel
        running_tests = Dict{String, DateTime}()
        if !Sys.iswindows() && isa(stdin, Base.TTY)
            t = current_task()
            stdin_monitor = @async begin
                term = REPL.Terminals.TTYTerminal("xterm", stdin, stdout, stderr)
                try
                    REPL.Terminals.raw!(term, true)
                    while true
                        c = read(term, Char)
                        if c == '\x3'
                            Base.throwto(t, InterruptException())
                            break
                        elseif c == '?'
                            println("Currently running: ")
                            tests = sort(collect(running_tests), by=x->x[2])
                            foreach(tests) do (test, date)
                                println(test, " (running for ", round(now()-date, Minute), ")")
                            end
                        end
                    end
                catch e
                    isa(e, InterruptException) || rethrow()
                finally
                    REPL.Terminals.raw!(term, false)
                end
            end
        end
        o_ts_duration = @elapsed Experimental.@sync begin
            for p in workers()
                @async begin
                    push!(all_tasks, current_task())
                    while length(tests) > 0
                        test = popfirst!(tests)
                        running_tests[test] = now()
                        wrkr = p
                        before = time()
                        resp, duration = try
                                r = remotecall_fetch(@Base.world(runtests, ∞), wrkr, test, test_path(test); seed=seed)
                                r, time() - before
                            catch e
                                isa(e, InterruptException) && return
                                Any[CapturedException(e, catch_backtrace())], time() - before
                            end
                        delete!(running_tests, test)
                        push!(results, (test, resp, duration))
                        if length(resp) == 1
                            print_testworker_errored(test, wrkr, exit_on_error ? nothing : resp[1])
                            if exit_on_error
                                skipped = length(tests)
                                empty!(tests)
                            elseif n > 1
                                # the worker encountered some failure, recycle it
                                # so future tests get a fresh environment
                                rmprocs(wrkr, waitfor=30)
                                p = addprocs_with_testenv(1)[1]
                                remotecall_fetch(include, p, "testdefs.jl")
                                if use_revise
                                    Distributed.remotecall_eval(Main, p, revise_init_expr)
                                end
                            end
                        else
                            print_testworker_stats(test, wrkr, resp)
                            if resp[end] > max_worker_rss
                                # the worker has reached the max-rss limit, recycle it
                                # so future tests start with a smaller working set
                                if n > 1
                                    rmprocs(wrkr, waitfor=30)
                                    p = addprocs_with_testenv(1)[1]
                                    remotecall_fetch(include, p, "testdefs.jl")
                                    if use_revise
                                        Distributed.remotecall_eval(Main, p, revise_init_expr)
                                    end
                                else # single process testing
                                    error("Halting tests. Memory limit reached : $resp > $max_worker_rss")
                                end
                            end
                       end
                    end
                    if p != 1
                        # Free up memory =)
                        rmprocs(p, waitfor=30)
                    end
                end
            end
        end

        n > 1 && length(node1_tests) > 1 && print("\nExecuting tests that run on node 1 only:\n")
        for t in node1_tests
            # As above, try to run each test
            # which must run on node 1. If
            # the test fails, catch the error,
            # and either way, append the results
            # to the overall aggregator
            isolate = true
            t == "SharedArrays" && (isolate = false)
            before = time()
            resp, duration = try
                    r = @invokelatest runtests(t, test_path(t), isolate, seed=seed) # runtests is defined by the include above
                    r, time() - before
                catch e
                    isa(e, InterruptException) && rethrow()
                    Any[CapturedException(e, catch_backtrace())], time() - before
                end
            if length(resp) == 1
                print_testworker_errored(t, 1, resp[1])
            else
                print_testworker_stats(t, 1, resp)
            end
            push!(results, (t, resp, duration))
        end
    catch e
        isa(e, InterruptException) || rethrow()
        # If the test suite was merely interrupted, still print the
        # summary, which can be useful to diagnose what's going on
        foreach(task -> begin
                istaskstarted(task) || return
                istaskdone(task) && return
                try
                    schedule(task, InterruptException(); error=true)
                catch ex
                    @error "InterruptException" exception=ex,catch_backtrace()
                end
            end, all_tasks)
        foreach(wait, all_tasks)
    finally
        if @isdefined stdin_monitor
            schedule(stdin_monitor, InterruptException(); error=true)
        end
    end

    #=
`   Construct a testset on the master node which will hold results from all the
    test files run on workers and on node1. The loop goes through the results,
    inserting them as children of the overall testset if they are testsets,
    handling errors otherwise.

    Since the workers don't return information about passing/broken tests, only
    errors or failures, those Result types get passed `nothing` for their test
    expressions (and expected/received result in the case of Broken).

    If a test failed, returning a `RemoteException`, the error is displayed and
    the overall testset has a child testset inserted, with the (empty) Passes
    and Brokens from the worker and the full information about all errors and
    failures encountered running the tests. This information will be displayed
    as a summary at the end of the test run.

    If a test failed, returning an `Exception` that is not a `RemoteException`,
    it is likely the julia process running the test has encountered some kind
    of internal error, such as a segfault.  The entire testset is marked as
    Errored, and execution continues until the summary at the end of the test
    run, where the test file is printed out as the "failed expression".
    =#
    Test.TESTSET_PRINT_ENABLE[] = false
    o_ts = Test.DefaultTestSet("Overall")
    o_ts.time_end = o_ts.time_start + o_ts_duration # manually populate the timing
    BuildkiteTestJSON.write_testset_json_files(@__DIR__, o_ts)
    Test.push_testset(o_ts)
    completed_tests = Set{String}()
    for (testname, (resp,), duration) in results
        push!(completed_tests, testname)
        if isa(resp, Test.DefaultTestSet)
            resp.time_end = resp.time_start + duration
            Test.push_testset(resp)
            Test.record(o_ts, resp)
            Test.pop_testset()
        elseif isa(resp, Test.TestSetException)
            fake = Test.DefaultTestSet(testname)
            fake.time_end = fake.time_start + duration
            for i in 1:resp.pass
                Test.record(fake, Test.Pass(:test, nothing, nothing, nothing, LineNumberNode(@__LINE__, @__FILE__)))
            end
            for i in 1:resp.broken
                Test.record(fake, Test.Broken(:test, nothing))
            end
            for t in resp.errors_and_fails
                Test.record(fake, t)
            end
            Test.push_testset(fake)
            Test.record(o_ts, fake)
            Test.pop_testset()
        else
            if !isa(resp, Exception)
                resp = ErrorException(string("Unknown result type : ", typeof(resp)))
            end
            # If this test raised an exception that is not a remote testset exception,
            # i.e. not a RemoteException capturing a TestSetException that means
            # the test runner itself had some problem, so we may have hit a segfault,
            # deserialization errors or something similar.  Record this testset as Errored.
            fake = Test.DefaultTestSet(testname)
            fake.time_end = fake.time_start + duration
            Test.record(fake, Test.Error(:nontest_error, testname, nothing, Base.ExceptionStack(Any[(resp, [])]), LineNumberNode(1), nothing))
            Test.push_testset(fake)
            Test.record(o_ts, fake)
            Test.pop_testset()
        end
    end
    for test in all_tests
        (test in completed_tests) && continue
        fake = Test.DefaultTestSet(test)
        Test.record(fake, Test.Error(:test_interrupted, test, nothing, Base.ExceptionStack(Any[("skipped", [])]), LineNumberNode(1), nothing))
        Test.push_testset(fake)
        Test.record(o_ts, fake)
        Test.pop_testset()
    end

    Test.TESTSET_PRINT_ENABLE[] = true
    println()
    # o_ts.verbose = true # set to true to show all timings when successful
    Test.print_test_results(o_ts, 1)
    if !o_ts.anynonpass
        printstyled("    SUCCESS\n"; bold=true, color=:green)
    else
        printstyled("    FAILURE\n\n"; bold=true, color=:red)
        skipped > 0 &&
            println("$skipped test", skipped > 1 ? "s were" : " was", " skipped due to failure.")
        println("The global RNG seed was 0x$(string(seed, base = 16)).\n")
        Test.print_test_errors(o_ts)
        throw(Test.FallbackTestSetException("Test run finished with errors"))
    end
end
