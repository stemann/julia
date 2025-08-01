# System Image Building

## [Building the Julia system image](@id Building-the-Julia-system-image)

Julia ships with a preparsed system image containing the contents of the `Base` module, named
`sys.ji`. This file is also precompiled into a shared library called `sys.{so,dll,dylib}` on
as many platforms as possible, so as to give vastly improved startup times. On systems that do
not ship with a precompiled system image file, one can be generated from the source files shipped
in Julia's `DATAROOTDIR/julia/base` folder.

Julia will by default generate its system image on half of the available system threads. This
may be controlled by the [`JULIA_IMAGE_THREADS`](@ref JULIA_IMAGE_THREADS) environment variable.

This operation is useful for multiple reasons. A user may:

  * Build a precompiled shared library system image on a platform that did not ship with one, thereby
    improving startup times.
  * Modify `Base`, rebuild the system image and use the new `Base` next time Julia is started.
  * Include a `userimg.jl` file that includes packages into the system image, thereby creating a system
    image that has packages embedded into the startup environment.

The [`PackageCompiler.jl` package](https://github.com/JuliaLang/PackageCompiler.jl) contains convenient
wrapper functions to automate this process.

## [System image optimized for multiple microarchitectures](@id sysimg-multi-versioning)

The system image can be compiled simultaneously for multiple CPU microarchitectures
under the same instruction set architecture (ISA). Multiple versions of the same function
may be created with minimum dispatch point inserted into shared functions
in order to take advantage of different ISA extensions or other microarchitecture features.
The version that offers the best performance will be selected automatically at runtime
based on available CPU features.

### Specifying multiple system image targets

A multi-microarchitecture system image can be enabled by passing multiple targets
during system image compilation. This can be done either with the [`JULIA_CPU_TARGET`](@ref JULIA_CPU_TARGET) make option
or with the `-C` command line option when running the compilation command manually.
Multiple targets are separated by `;` in the option string.
The syntax for each target is a CPU name followed by multiple features separated by `,`.
All features supported by LLVM are supported and a feature can be disabled with a `-` prefix.
(`+` prefix is also allowed and ignored to be consistent with LLVM syntax).
Additionally, a few special features are supported to control the function cloning behavior.

!!! note
    It is good practice to specify either `clone_all` or `base(<n>)` for every target apart from the first one. This makes it explicit which targets have all functions cloned, and which targets are based on other targets. If this is not done, the default behavior is to not clone every function, and to use the first target's function definition as the fallback when not cloning a function.

1. `clone_all`

    By default, only functions that are the most likely to benefit from
    the microarchitecture features will be cloned.
    When `clone_all` is specified for a target, however,
    **all** functions in the system image will be cloned for the target.
    The negative form `-clone_all` can be used to prevent the built-in
    heuristic from cloning all functions.

2. `base(<n>)`

    Where `<n>` is a placeholder for a non-negative number (e.g. `base(0)`, `base(1)`).
    By default, a partially cloned (i.e. not `clone_all`) target will use functions
    from the default target (first one specified) if a function is not cloned.
    This behavior can be changed by specifying a different base with the `base(<n>)` option.
    The `n`th target (0-based) will be used as the base target instead of the default (`0`th) one.
    The base target has to be either `0` or another `clone_all` target.
    Specifying a non-`clone_all` target as the base target will cause an error.

3. `opt_size`

    This causes the function for the target to be optimized for size when there isn't a significant
    runtime performance impact. This corresponds to `-Os` GCC and Clang option.

4. `min_size`

    This causes the function for the target to be optimized for size that might have
    a significant runtime performance impact. This corresponds to `-Oz` Clang option.

As an example, at the time of this writing, the following string is used in the creation of
the official `x86_64` Julia binaries downloadable from julialang.org:

```
generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)
```

This creates a system image with three separate targets; one for a generic `x86_64`
processor, one with a `sandybridge` ISA (explicitly excluding `xsaveopt`) that explicitly
clones all functions, and one targeting the `haswell` ISA, based off of the `sandybridge`
sysimg version, and also excluding `rdrnd`. When a Julia implementation loads the
generated sysimg, it will check the host processor for matching CPU capability flags,
enabling the highest ISA level possible. Note that the base level (`generic`) requires
the `cx16` instruction, which is disabled in some virtualization software and must be
enabled for the `generic` target to be loaded. Alternatively, a sysimg could be generated
with the target `generic,-cx16` for greater compatibility, however note that this may cause
performance and stability problems in some code.

### Implementation overview

This is a brief overview of different part involved in the implementation.
See code comments for each components for more implementation details.

1. System image compilation

    The parsing and cloning decision are done in `src/processor*`.
    We currently support cloning of function based on the present of loops, simd instructions,
    or other math operations (e.g. fastmath, fma, muladd).
    This information is passed on to `src/llvm-multiversioning.cpp` which does the actual cloning.
    In addition to doing the cloning and insert dispatch slots
    (see comments in `MultiVersioning::runOnModule` for how this is done),
    the pass also generates metadata so that the runtime can load and initialize the
    system image correctly.
    A detailed description of the metadata is available in `src/processor.h`.

2. System image loading

    The loading and initialization of the system image is done in `src/processor*` by
    parsing the metadata saved during system image generation.
    Host feature detection and selection decision are done in `src/processor_*.cpp`
    depending on the ISA. The target selection will prefer exact CPU name match,
    larger vector register size, and larger number of features.
    An overview of this process is in `src/processor.cpp`.

## Trimming

System images are typically quite large, since Base includes a lot of functionality, and by
default system images also include several packages such as LinearAlgebra for convenience
and backwards compatibility. Most programs will use only a fraction of the functions in
these packages. Therefore it makes sense to build binaries that exclude unused functions
to save space, referred to as "trimming".

While the basic idea of trimming is sound, Julia has dynamic and reflective features that make it
difficult (or impossible) to know in general which functions are unused. As an extreme example,
consider code like

```
getglobal(Base, Symbol(readchomp(stdin)))(1)
```

This code reads a function name from `stdin` and calls the named function from Base on the value
`1`. In this case it is impossible to predict which function will be called, so no functions
can reliably be considered "unused". With some noteworthy exceptions (Julia's own REPL being
one of them), most real-world programs do not do things like this.

Less extreme cases occur, for example, when there are type instabilities that make it impossible
for the compiler to predict which method will be called. However, if code is well-typed and does
not use reflection, a complete and (hopefully) relatively small set of needed methods can be
determined, and the rest can be removed. The `--trim` command-line option requests this kind of
compilation.

When `--trim` is specified in a command used to build a system image, the compiler begins
tracing calls starting at methods marked using `Base.Experimental.entrypoint`. If a call is too
dynamic to reasonably narrow down the possible call targets, an error is given at compile
time showing the location of the call. For testing purposes, it is possible to skip these
errors by specifying `--trim=unsafe` or `--trim=unsafe-warn`. Then you will get a system
image built, but it may crash at run time if needed code is not present.

It typically makes sense to specify `--strip-ir` along with `--trim`, since trimmed binaries
are fully compiled and therefore don't need Julia IR. At some point we may make `--trim` imply
`--strip-ir`, but for now we have kept them orthogonal.

To get the smallest possible binary, it will also help to specify `--strip-metadata` and
run the Unix `strip` utility. However, those steps remove Julia-specific and native (DWARF format)
debug info, respectively, and so will make debugging more difficult.

### Common problems

- The Base global variables `stdin`, `stdout`, and `stderr` are non-constant and so their
  types are not known. All printing should use a specific IO object with a known type.
  The easiest substitution is to use `print(Core.stdout, x)` instead of `print(x)` or
  `print(stdout, x)`.
- Use tools like [JET.jl](https://github.com/aviatesk/JET.jl),
  [Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl), and/or
  [SnoopCompile](https://github.com/timholy/SnoopCompile.jl)
  to identify failures of type-inference, and follow our [Performance Tips](@ref) to fix them.

### Compatibility concerns

We have identified many small changes to Base that significantly increase the set of programs
that can be reliably trimmed. Unfortunately some of those changes would be considered breaking,
and so are only applied when trimming is requested (this is done by an external build script,
currently maintained inside the test suite as `contrib/juliac/juliac-buildscript.jl`).
Therefore in many cases trimming will require you to opt in to new variants of Base and some
standard libraries.

If you want to use trimming, it is important to set up continuous integration testing that
performs a trimmed build and fully tests the resulting program.
Fortunately, if your program successfully compiles with `--trim` then it is very likely to work
the same as it did before. However, CI is needed to ensure that your program continues to build
with trimming as you develop it.

Package authors may wish to test that their package is "trimming safe", however this is impossible
in general. Trimming is only expected to work given concrete entry points such as `main()` and
library entry points meant to be called from outside Julia. For generic packages, existing tests
for type stability like `@inferred` and `JET.@report_call` are about as close as you can get to checking
trim compatibility.

Trimming also introduces new compatibility issues between minor versions of Julia. At this time,
we are not able to guarantee that a program that can be trimmed in one version of Julia
can also be trimmed in all future versions of Julia. However, breakage of that kind is expected
to be rare. We also plan to try to *increase* the set of programs that can be trimmed over time.
