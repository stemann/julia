# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    Complex{T<:Real} <: Number

Complex number type with real and imaginary part of type `T`.

`ComplexF16`, `ComplexF32` and `ComplexF64` are aliases for
`Complex{Float16}`, `Complex{Float32}` and `Complex{Float64}` respectively.

See also: [`Real`](@ref), [`complex`](@ref), [`real`](@ref).
"""
struct Complex{T<:Real} <: Number
    re::T
    im::T
end
Complex(x::Real, y::Real) = Complex(promote(x,y)...)
Complex(x::Real) = Complex(x, zero(x))

"""
    im

The imaginary unit.

See also: [`imag`](@ref), [`angle`](@ref), [`complex`](@ref).

# Examples
```jldoctest
julia> im * im
-1 + 0im

julia> (2.0 + 3im)^2
-5.0 + 12.0im
```
"""
const im = Complex(false, true)

const ComplexF64  = Complex{Float64}
const ComplexF32  = Complex{Float32}
const ComplexF16  = Complex{Float16}

Complex{T}(x::Real) where {T<:Real} = Complex{T}(x,0)
Complex{T}(z::Complex) where {T<:Real} = Complex{T}(real(z),imag(z))
(::Type{T})(z::Complex) where {T<:Real} =
    isreal(z) ? T(real(z))::T : throw(InexactError(nameof(T), T, z))

Complex(z::Complex) = z

promote_rule(::Type{Complex{T}}, ::Type{S}) where {T<:Real,S<:Real} =
    Complex{promote_type(T,S)}
promote_rule(::Type{Complex{T}}, ::Type{Complex{S}}) where {T<:Real,S<:Real} =
    Complex{promote_type(T,S)}

widen(::Type{Complex{T}}) where {T} = Complex{widen(T)}

float(::Type{Complex{T}}) where {T<:AbstractFloat} = Complex{T}
float(::Type{Complex{T}}) where {T} = Complex{float(T)}

"""
    real(z)

Return the real part of the complex number `z`.

See also: [`imag`](@ref), [`reim`](@ref), [`complex`](@ref), [`isreal`](@ref), [`Real`](@ref).

# Examples
```jldoctest
julia> real(1 + 3im)
1
```
"""
real(z::Complex) = z.re

"""
    imag(z)

Return the imaginary part of the complex number `z`.

See also: [`conj`](@ref), [`reim`](@ref), [`adjoint`](@ref), [`angle`](@ref).

# Examples
```jldoctest
julia> imag(1 + 3im)
3
```
"""
imag(z::Complex) = z.im
real(x::Real) = x
imag(x::Real) = zero(x)

"""
    reim(z)

Return a tuple of the real and imaginary parts of the complex number `z`.

# Examples
```jldoctest
julia> reim(1 + 3im)
(1, 3)
```
"""
reim(z) = (real(z), imag(z))

"""
    real(T::Type)

Return the type that represents the real part of a value of type `T`.
e.g: for `T == Complex{R}`, returns `R`.
Equivalent to `typeof(real(zero(T)))`.

# Examples
```jldoctest
julia> real(Complex{Int})
Int64

julia> real(Float64)
Float64
```
"""
real(T::Type) = typeof(real(zero(T)))
real(::Type{T}) where {T<:Real} = T
real(C::Type{<:Complex}) = fieldtype(C, 1)
real(::Type{Union{}}, slurp...) = Union{}(im)

"""
    isreal(x)::Bool

Test whether `x` or all its elements are numerically equal to some real number
including infinities and NaNs. `isreal(x)` is true if `isequal(x, real(x))`
is true.

# Examples
```jldoctest
julia> isreal(5.)
true

julia> isreal(1 - 3im)
false

julia> isreal(Inf + 0im)
true

julia> isreal([4.; complex(0,1)])
false
```
"""
isreal(x::Real) = true
isreal(z::Complex) = iszero(imag(z))
isinteger(z::Complex) = isreal(z) & isinteger(real(z))
isfinite(z::Complex) = isfinite(real(z)) & isfinite(imag(z))
isnan(z::Complex) = isnan(real(z)) | isnan(imag(z))
isinf(z::Complex) = isinf(real(z)) | isinf(imag(z))
iszero(z::Complex) = iszero(real(z)) & iszero(imag(z))
isone(z::Complex) = isone(real(z)) & iszero(imag(z))

"""
    complex(r, [i])

Convert real numbers or arrays to complex. `i` defaults to zero.

# Examples
```jldoctest
julia> complex(7)
7 + 0im
```
"""
complex(z::Complex) = z
complex(x::Real) = Complex(x)
complex(x::Real, y::Real) = Complex(x, y)

"""
    complex(T::Type)

Return an appropriate type which can represent a value of type `T` as a complex number.
Equivalent to `typeof(complex(zero(T)))` if `T` does not contain `Missing`.

# Examples
```jldoctest
julia> complex(Complex{Int})
Complex{Int64}

julia> complex(Int)
Complex{Int64}

julia> complex(Union{Int, Missing})
Union{Missing, Complex{Int64}}
```
"""
complex(::Type{T}) where {T<:Real} = Complex{T}
complex(::Type{Complex{T}}) where {T<:Real} = Complex{T}

flipsign(x::Complex, y::Real) = ifelse(signbit(y), -x, x)

function show(io::IO, z::Complex)
    r, i = reim(z)
    compact = get(io, :compact, false)::Bool
    show(io, r)
    if signbit(i) && !isnan(i)
        print(io, compact ? "-" : " - ")
        if isa(i,Signed) && !isa(i,BigInt) && i == typemin(typeof(i))
            show(io, -widen(i))
        else
            show(io, -i)
        end
    else
        print(io, compact ? "+" : " + ")
        show(io, i)
    end
    if !(isa(i,Signed) || isa(i,AbstractFloat) && isfinite(i))
        print(io, "*")
    end
    print(io, "im")
end
show(io::IO, z::Complex{Bool}) =
    print(io, z == im ? "im" : "Complex($(z.re),$(z.im))")

function show_unquoted(io::IO, z::Complex, ::Int, prec::Int)
    if operator_precedence(:+) <= prec
        print(io, "(")
        show(io, z)
        print(io, ")")
    else
        show(io, z)
    end
end

function read(s::IO, ::Type{Complex{T}}) where T<:Real
    r = read(s,T)
    i = read(s,T)
    Complex{T}(r,i)
end
function write(s::IO, z::Complex)
    write(s,real(z),imag(z))
end

## byte order swaps: real and imaginary part are swapped individually
bswap(z::Complex) = Complex(bswap(real(z)), bswap(imag(z)))

## equality and hashing of complex numbers ##

==(z::Complex, w::Complex) = (real(z) == real(w)) & (imag(z) == imag(w))
==(z::Complex, x::Real) = isreal(z) && real(z) == x
==(x::Real, z::Complex) = isreal(z) && real(z) == x

isequal(z::Complex, w::Complex) = isequal(real(z),real(w))::Bool & isequal(imag(z),imag(w))::Bool
isequal(z::Complex, w::Real) = isequal(real(z),w)::Bool & isequal(imag(z),zero(w))::Bool
isequal(z::Real, w::Complex) = isequal(z,real(w))::Bool & isequal(zero(z),imag(w))::Bool

in(x::Complex, r::AbstractRange{<:Real}) = isreal(x) && real(x) in r

if UInt === UInt64
    const h_imag = 0x32a7a07f3e7cd1f9
else
    const h_imag = 0x3e7cd1f9
end
const hash_0_imag = hash(0, h_imag)

function hash(z::Complex, h::UInt)
    # TODO: with default argument specialization, this would be better:
    # hash(real(z), h ⊻ hash(imag(z), h ⊻ h_imag) ⊻ hash(0, h ⊻ h_imag))
    hash(real(z), h ⊻ hash(imag(z), h_imag) ⊻ hash_0_imag)
end

## generic functions of complex numbers ##

"""
    conj(z)

Compute the complex conjugate of a complex number `z`.

See also: [`angle`](@ref), [`adjoint`](@ref).

# Examples
```jldoctest
julia> conj(1 + 3im)
1 - 3im
```
"""
conj(z::Complex) = Complex(real(z),-imag(z))
abs(z::Complex)  = hypot(real(z), imag(z))
abs2(z::Complex) = real(z)*real(z) + imag(z)*imag(z)
function inv(z::Complex)
    c, d = reim(z)
    (isinf(c) | isinf(d)) && return complex(copysign(zero(c), c), flipsign(-zero(d), d))
    complex(c, -d)/(c * c + d * d)
end
inv(z::Complex{<:Integer}) = inv(float(z))

+(z::Complex) = Complex(+real(z), +imag(z))
-(z::Complex) = Complex(-real(z), -imag(z))
+(z::Complex, w::Complex) = Complex(real(z) + real(w), imag(z) + imag(w))
-(z::Complex, w::Complex) = Complex(real(z) - real(w), imag(z) - imag(w))
*(z::Complex, w::Complex) = Complex(real(z) * real(w) - imag(z) * imag(w),
                                    real(z) * imag(w) + imag(z) * real(w))

muladd(z::Complex, w::Complex, x::Complex) =
    Complex(muladd(real(z), real(w), -muladd(imag(z), imag(w), -real(x))),
            muladd(real(z), imag(w),  muladd(imag(z), real(w),  imag(x))))

# handle Bool and Complex{Bool}
# avoid type signature ambiguity warnings
+(x::Bool, z::Complex{Bool}) = Complex(x + real(z), imag(z))
+(z::Complex{Bool}, x::Bool) = Complex(real(z) + x, imag(z))
-(x::Bool, z::Complex{Bool}) = Complex(x - real(z), - imag(z))
-(z::Complex{Bool}, x::Bool) = Complex(real(z) - x, imag(z))
*(x::Bool, z::Complex{Bool}) = Complex(x * real(z), x * imag(z))
*(z::Complex{Bool}, x::Bool) = Complex(real(z) * x, imag(z) * x)

+(x::Bool, z::Complex) = Complex(x + real(z), imag(z))
+(z::Complex, x::Bool) = Complex(real(z) + x, imag(z))
-(x::Bool, z::Complex) = Complex(x - real(z), - imag(z))
-(z::Complex, x::Bool) = Complex(real(z) - x, imag(z))
*(x::Bool, z::Complex) = Complex(x * real(z), x * imag(z))
*(z::Complex, x::Bool) = Complex(real(z) * x, imag(z) * x)

+(x::Real, z::Complex{Bool}) = Complex(x + real(z), imag(z))
+(z::Complex{Bool}, x::Real) = Complex(real(z) + x, imag(z))
function -(x::Real, z::Complex{Bool})
    # we don't want the default type for -(Bool)
    re = x-real(z)
    Complex(re, - oftype(re, imag(z)))
end
-(z::Complex{Bool}, x::Real) = Complex(real(z) - x, imag(z))
*(x::Real, z::Complex{Bool}) = Complex(x * real(z), x * imag(z))
*(z::Complex{Bool}, x::Real) = Complex(real(z) * x, imag(z) * x)

# adding or multiplying real & complex is common
+(x::Real, z::Complex) = Complex(x + real(z), imag(z))
+(z::Complex, x::Real) = Complex(x + real(z), imag(z))
function -(x::Real, z::Complex)
    # we don't want the default type for -(Bool)
    re = x - real(z)
    Complex(re, - oftype(re, imag(z)))
end
-(z::Complex, x::Real) = Complex(real(z) - x, imag(z))
*(x::Real, z::Complex) = Complex(x * real(z), x * imag(z))
*(z::Complex, x::Real) = Complex(x * real(z), x * imag(z))

muladd(x::Real, z::Complex, y::Union{Real,Complex}) = muladd(z, x, y)
muladd(z::Complex, x::Real, y::Real) = Complex(muladd(real(z),x,y), imag(z)*x)
muladd(z::Complex, x::Real, w::Complex) =
    Complex(muladd(real(z),x,real(w)), muladd(imag(z),x,imag(w)))
muladd(x::Real, y::Real, z::Complex) = Complex(muladd(x,y,real(z)), imag(z))
muladd(z::Complex, w::Complex, x::Real) =
    Complex(muladd(real(z), real(w), -muladd(imag(z), imag(w), -x)),
            muladd(real(z), imag(w), imag(z) * real(w)))

/(a::R, z::S) where {R<:Real,S<:Complex} = (T = promote_type(R,S); a*inv(T(z)))
/(z::Complex, x::Real) = Complex(real(z)/x, imag(z)/x)

function /(a::Complex{T}, b::Complex{T}) where T<:Real
    are = real(a); aim = imag(a); bre = real(b); bim = imag(b)
    if (isinf(bre) | isinf(bim))
        if isfinite(a)
            return complex(zero(T)*sign(are)*sign(bre), -zero(T)*sign(aim)*sign(bim))
        end
        return T(NaN)+T(NaN)*im
    end
    if abs(bre) <= abs(bim)
        r = bre / bim
        den = bim + r*bre
        Complex((are*r + aim)/den, (aim*r - are)/den)
    else
        r = bim / bre
        den = bre + r*bim
        Complex((are + aim*r)/den, (aim - are*r)/den)
    end
end

function /(z::Complex{T}, w::Complex{T}) where {T<:Union{Float16,Float32}}
    c, d = reim(widen(w))
    a, b = reim(widen(z))
    if (isinf(c) | isinf(d))
        if isfinite(z)
            return complex(zero(T)*sign(real(z))*sign(real(w)), -zero(T)*sign(imag(z))*sign(imag(w)))
        end
        return T(NaN)+T(NaN)*im
    end
    mag = inv(muladd(c, c, d^2))
    re_part = muladd(a, c, b*d)
    im_part = muladd(b, c, -a*d)
    return oftype(z, Complex(re_part*mag, im_part*mag))
end

# robust complex division for double precision
# variables are scaled & unscaled to avoid over/underflow, if necessary
# based on arxiv.1210.4539
#             a + i*b
#  p + i*q = ---------
#             c + i*d
function /(z::ComplexF64, w::ComplexF64)
    a, b = reim(z); c, d = reim(w)
    absa = abs(a); absb = abs(b);  ab = absa >= absb ? absa : absb # equiv. to max(abs(a),abs(b)) but without NaN-handling (faster)
    absc = abs(c); absd = abs(d);  cd = absc >= absd ? absc : absd
    if (isinf(c) | isinf(d))
        if isfinite(z)
            return complex(0.0*sign(a)*sign(c), -0.0*sign(b)*sign(d))
        end
        return NaN+NaN*im
    end
    halfov = 0.5*floatmax(Float64)              # overflow threshold
    twounϵ = floatmin(Float64)*2.0/eps(Float64) # underflow threshold

    # actual division operations
    if  ab>=halfov || ab<=twounϵ || cd>=halfov || cd<=twounϵ # over/underflow case
        p,q = scaling_cdiv(a,b,c,d,ab,cd) # scales a,b,c,d before division (unscales after)
    else
        p,q = cdiv(a,b,c,d)
    end

    return ComplexF64(p,q)
end

# sub-functionality for /(z::ComplexF64, w::ComplexF64)
@inline function cdiv(a::Float64, b::Float64, c::Float64, d::Float64)
    if abs(d)<=abs(c)
        p,q = robust_cdiv1(a,b,c,d)
    else
        p,q = robust_cdiv1(b,a,d,c)
        q = -q
    end
    return p,q
end
@noinline function scaling_cdiv(a::Float64, b::Float64, c::Float64, d::Float64, ab::Float64, cd::Float64)
    # this over/underflow functionality is outlined for performance, cf. #29688
    a,b,c,d,s = scaleargs_cdiv(a,b,c,d,ab,cd)
    p,q = cdiv(a,b,c,d)
    return p*s,q*s
end
function scaleargs_cdiv(a::Float64, b::Float64, c::Float64, d::Float64, ab::Float64, cd::Float64)
    ϵ      = eps(Float64)
    halfov = 0.5*floatmax(Float64)
    twounϵ = floatmin(Float64)*2.0/ϵ
    bs     = 2.0/(ϵ*ϵ)

    # scaling
    s = 1.0
    if ab >= halfov
        a*=0.5; b*=0.5; s*=2.0  # scale down a,b
    elseif ab <= twounϵ
        a*=bs;  b*=bs;  s/=bs   # scale up a,b
    end
    if cd >= halfov
        c*=0.5; d*=0.5; s*=0.5  # scale down c,d
    elseif cd <= twounϵ
        c*=bs;  d*=bs;  s*=bs   # scale up c,d
    end

    return a,b,c,d,s
end
@inline function robust_cdiv1(a::Float64, b::Float64, c::Float64, d::Float64)
    r = d/c
    t = 1.0/(c+d*r)
    p = robust_cdiv2(a,b,c,d,r,t)
    q = robust_cdiv2(b,-a,c,d,r,t)
    return p,q
end
function robust_cdiv2(a::Float64, b::Float64, c::Float64, d::Float64, r::Float64, t::Float64)
    if r != 0
        br = b*r
        return (br != 0 ? (a+br)*t : a*t + (b*t)*r)
    else
        return (a + d*(b/c)) * t
    end
end

function inv(z::Complex{T}) where T<:Union{Float16,Float32}
    c, d = reim(widen(z))
    (isinf(c) | isinf(d)) && return complex(copysign(zero(T), c), flipsign(-zero(T), d))
    mag = inv(muladd(c, c, d^2))
    return oftype(z, Complex(c*mag, -d*mag))
end
function inv(w::ComplexF64)
    c, d = reim(w)
    absc, absd = abs(c), abs(d)
    cd, dc = ifelse(absc>absd, (absc, absd), (absd, absc))
    # no overflow from abs2
    if sqrt(floatmin(Float64)/2) <= cd <= sqrt(floatmax(Float64)/2)
        return conj(w) / muladd(cd, cd, dc*dc)
    end
    (isinf(c) | isinf(d)) && return complex(copysign(0.0, c), flipsign(-0.0, d))

    ϵ  = eps(Float64)
    bs = 2/(ϵ*ϵ)

    # scaling
    s = 1.0
    if cd >= floatmax(Float64)/2
        c *= 0.5; d *= 0.5; s = 0.5 # scale down c, d
    elseif cd <= 2floatmin(Float64)/ϵ
        c *= bs;  d *= bs;  s = bs  # scale up c, d
    end

    # inversion operations
    if absd <= absc
        p, q = robust_cinv(c, d)
    else
        q, p = robust_cinv(-d, -c)
    end
    return ComplexF64(p*s, q*s)
end
function robust_cinv(c::Float64, d::Float64)
    r = d/c
    z = muladd(d, r, c)
    p = 1.0/z
    q = -r/z
    return p, q
end

function ssqs(x::T, y::T) where T<:Real
    k::Int = 0
    ρ = x*x + y*y
    if !isfinite(ρ) && (isinf(x) || isinf(y))
        ρ = convert(T, Inf)
    elseif isinf(ρ) || (ρ==0 && (x!=0 || y!=0)) || ρ<nextfloat(zero(T))/(2*eps(T)^2)
        m::T = max(abs(x), abs(y))
        k = m==0 ? m : exponent(m)
        xk, yk = ldexp(x,-k), ldexp(y,-k)
        ρ = xk*xk + yk*yk
    end
    ρ, k
end

function sqrt(z::Complex)
    z = float(z)
    x, y = reim(z)
    if x==y==0
        return Complex(zero(x),y)
    end
    ρ, k::Int = ssqs(x, y)
    if isfinite(x) ρ=ldexp(abs(x),-k)+sqrt(ρ) end
    if isodd(k)
        k = div(k-1,2)
    else
        k = div(k,2)-1
        ρ += ρ
    end
    ρ = ldexp(sqrt(ρ),k) #sqrt((abs(z)+abs(x))/2) without over/underflow
    ξ = ρ
    η = y
    if ρ != 0
        if isfinite(η) η=(η/ρ)/2 end
        if x<0
            ξ = abs(η)
            η = copysign(ρ,y)
        end
    end
    Complex(ξ,η)
end

# function sqrt(z::Complex)
#     rz = float(real(z))
#     iz = float(imag(z))
#     r = sqrt((hypot(rz,iz)+abs(rz))/2)
#     if r == 0
#         return Complex(zero(iz), iz)
#     end
#     if rz >= 0
#         return Complex(r, iz/r/2)
#     end
#     return Complex(abs(iz)/r/2, copysign(r,iz))
# end

"""
    cis(x)

More efficient method for `exp(im*x)` by using Euler's formula: ``\\cos(x) + i \\sin(x) = \\exp(i x)``.

See also [`cispi`](@ref), [`sincos`](@ref), [`exp`](@ref), [`angle`](@ref).

# Examples
```jldoctest
julia> cis(π) ≈ -1
true
```
"""
function cis end
function cis(theta::Real)
    s, c = sincos(theta)
    Complex(c, s)
end

function cis(z::Complex)
    v = exp(-imag(z))
    s, c = sincos(real(z))
    Complex(v * c, v * s)
end

"""
    cispi(x)

More accurate method for `cis(pi*x)` (especially for large `x`).

See also [`cis`](@ref), [`sincospi`](@ref), [`exp`](@ref), [`angle`](@ref).

# Examples
```jldoctest
julia> cispi(10000)
1.0 + 0.0im

julia> cispi(0.25 + 1im)
0.030556854645954562 + 0.03055685464595456im
```

!!! compat "Julia 1.6"
    This function requires Julia 1.6 or later.
"""
function cispi end
cispi(theta::Real) = Complex(reverse(sincospi(theta))...)

function cispi(z::Complex)
    v = exp(-(pi*imag(z)))
    s, c = sincospi(real(z))
    Complex(v * c, v * s)
end

"""
    angle(z)

Compute the phase angle in radians of a complex number `z`.

Returns a number `-pi ≤ angle(z) ≤ pi`, and is thus discontinuous
along the negative real axis.

See also: [`atan`](@ref), [`cis`](@ref), [`rad2deg`](@ref).

# Examples
```jldoctest
julia> rad2deg(angle(1 + im))
45.0

julia> rad2deg(angle(1 - im))
-45.0

julia> rad2deg(angle(-1 + 1e-20im))
180.0

julia> rad2deg(angle(-1 - 1e-20im))
-180.0
```
"""
angle(z::Complex) = atan(imag(z), real(z))

function log(z::Complex)
    z = float(z)
    T = typeof(real(z))
    T1  = convert(T,5)/convert(T,4)
    T2  = convert(T,3)
    ln2 = log(convert(T,2))  #0.6931471805599453
    x, y = reim(z)
    ρ, k = ssqs(x,y)
    ax = abs(x)
    ay = abs(y)
    if ax < ay
        θ, β = ax, ay
    else
        θ, β = ay, ax
    end
    if k==0 && (0.5 < β*β) && (β <= T1 || ρ < T2)
        ρρ = log1p((β-1)*(β+1)+θ*θ)/2
    else
        ρρ = log(ρ)/2 + k*ln2
    end
    Complex(ρρ, angle(z))
end

# function log(z::Complex)
#     ar = abs(real(z))
#     ai = abs(imag(z))
#     if ar < ai
#         r = ar/ai
#         re = log(ai) + log1p(r*r)/2
#     else
#         if ar == 0
#             re = isnan(ai) ? ai : -inv(ar)
#         elseif isinf(ai)
#             re = oftype(ar,Inf)
#         else
#             r = ai/ar
#             re = log(ar) + log1p(r*r)/2
#         end
#     end
#     Complex(re, angle(z))
# end

function log10(z::Complex)
    a = log(z)
    a/log(oftype(real(a),10))
end
function log2(z::Complex)
    a = log(z)
    a/log(oftype(real(a),2))
end

function exp(z::Complex)
    zr, zi = reim(z)
    if isnan(zr)
        Complex(zr, zi==0 ? zi : zr)
    elseif !isfinite(zi)
        if zr == Inf
            Complex(-zr, oftype(zr,NaN))
        elseif zr == -Inf
            Complex(-zero(zr), copysign(zero(zi), zi))
        else
            Complex(oftype(zr,NaN), oftype(zi,NaN))
        end
    else
        er = exp(zr)
        if iszero(zi)
            Complex(er, zi)
        else
            s, c = sincos(zi)
            Complex(er * c, er * s)
        end
    end
end

function expm1(z::Complex{T}) where T<:Real
    Tf = float(T)
    zr,zi = reim(z)
    if isnan(zr)
        Complex(zr, zi==0 ? zi : zr)
    elseif !isfinite(zi)
        if zr == Inf
            Complex(-zr, oftype(zr,NaN))
        elseif zr == -Inf
            Complex(-one(zr), copysign(zero(zi), zi))
        else
            Complex(oftype(zr,NaN), oftype(zi,NaN))
        end
    else
        erm1 = expm1(zr)
        if zi == 0
            Complex(erm1, zi)
        else
            er = erm1+one(erm1)
            if isfinite(er)
                wr = erm1 - 2 * er * (sin(convert(Tf, 0.5) * zi))^2
                return Complex(wr, er * sin(zi))
            else
                s, c = sincos(zi)
                return Complex(er * c, er * s)
            end
        end
    end
end

function log1p(z::Complex{T}) where T
    zr,zi = reim(z)
    if isfinite(zr)
        isinf(zi) && return log(z)
        # This is based on a well-known trick for log1p of real z,
        # allegedly due to Kahan, only modified to handle real(u) <= 0
        # differently to avoid inaccuracy near z==-2 and for correct branch cut
        u = one(float(T)) + z
        u == 1 ? convert(typeof(u), z) : real(u) <= 0 ? log(u) : log(u)*(z/(u-1))
    elseif isnan(zr)
        Complex(zr, zr)
    elseif isfinite(zi)
        Complex(T(Inf), copysign(zr > 0 ? zero(T) : convert(T, pi), zi))
    else
        Complex(T(Inf), T(NaN))
    end
end

function exp2(z::Complex{T}) where T
    z = float(z)
    er = exp2(real(z))
    theta = imag(z) * log(convert(float(T), 2))
    s, c = sincos(theta)
    Complex(er * c, er * s)
end

function exp10(z::Complex{T}) where T
    z = float(z)
    er = exp10(real(z))
    theta = imag(z) * log(convert(float(T), 10))
    s, c = sincos(theta)
    Complex(er * c, er * s)
end

# _cpow helper function to avoid method ambiguity with ^(::Complex,::Real)
function _cpow(z::Union{T,Complex{T}}, p::Union{T,Complex{T}}) where T
    z = float(z)
    p = float(p)
    Tf = float(T)
    if isreal(p)
        pᵣ = real(p)
        if isinteger(pᵣ) && abs(pᵣ) < typemax(Int32)
            # |p| < typemax(Int32) serves two purposes: it prevents overflow
            # when converting p to Int, and it also turns out to be roughly
            # the crossover point for exp(p*log(z)) or similar to be faster.
            if iszero(pᵣ) # fix signs of imaginary part for z^0
                zer = flipsign(copysign(zero(Tf),pᵣ), imag(z))
                return Complex(one(Tf), zer)
            end
            ip = convert(Int, pᵣ)
            if isreal(z)
                zᵣ = real(z)
                if ip < 0
                    iszero(z) && return Complex(Tf(NaN),Tf(NaN))
                    re = power_by_squaring(inv(zᵣ), -ip)
                    im = -imag(z)
                else
                    re = power_by_squaring(zᵣ, ip)
                    im = imag(z)
                end
                # slightly tricky to get the correct sign of zero imag. part
                return Complex(re, ifelse(iseven(ip) & signbit(zᵣ), -im, im))
            else
                return ip < 0 ? power_by_squaring(inv(z), -ip) : power_by_squaring(z, ip)
            end
        elseif isreal(z)
            # (note: if both z and p are complex with ±0.0 imaginary parts,
            #  the sign of the ±0.0 imaginary part of the result is ambiguous)
            if iszero(real(z))
                return pᵣ > 0 ? complex(z) : Complex(Tf(NaN),Tf(NaN)) # 0 or NaN+NaN*im
            elseif real(z) > 0
                return Complex(real(z)^pᵣ, z isa Real ? ifelse(real(z) < 1, -imag(p), imag(p)) : flipsign(imag(z), pᵣ))
            else
                zᵣ = real(z)
                rᵖ = (-zᵣ)^pᵣ
                if isfinite(pᵣ)
                    # figuring out the sign of 0.0 when p is a complex number
                    # with zero imaginary part and integer/2 real part could be
                    # improved here, but it's not clear if it's worth it…
                    return rᵖ * complex(cospi(pᵣ), flipsign(sinpi(pᵣ),imag(z)))
                else
                    iszero(rᵖ) && return zero(Complex{Tf}) # no way to get correct signs of 0.0
                    return Complex(Tf(NaN),Tf(NaN)) # non-finite phase angle or NaN input
                end
            end
        else
            rᵖ = abs(z)^pᵣ
            ϕ = pᵣ*angle(z)
        end
    elseif isreal(z)
        iszero(z) && return real(p) > 0 ? complex(z) : Complex(Tf(NaN),Tf(NaN)) # 0 or NaN+NaN*im
        zᵣ = real(z)
        pᵣ, pᵢ = reim(p)
        if zᵣ > 0
            rᵖ = zᵣ^pᵣ
            ϕ = pᵢ*log(zᵣ)
        else
            r = -zᵣ
            θ = copysign(Tf(π),imag(z))
            rᵖ = r^pᵣ * exp(-pᵢ*θ)
            ϕ = pᵣ*θ + pᵢ*log(r)
        end
    else
        pᵣ, pᵢ = reim(p)
        r = abs(z)
        θ = angle(z)
        rᵖ = r^pᵣ * exp(-pᵢ*θ)
        ϕ = pᵣ*θ + pᵢ*log(r)
    end

    if isfinite(ϕ)
        return rᵖ * cis(ϕ)
    else
        iszero(rᵖ) && return zero(Complex{Tf}) # no way to get correct signs of 0.0
        return Complex(Tf(NaN),Tf(NaN)) # non-finite phase angle or NaN input
    end
end
^(z::Complex{T}, p::Complex{T}) where T<:Real = _cpow(z, p)
^(z::Complex{T}, p::T) where T<:Real = _cpow(z, p)
^(z::T, p::Complex{T}) where T<:Real = _cpow(z, p)

^(z::Complex, n::Bool) = n ? z : one(z)
^(z::Complex, n::Integer) = z^Complex(n)

^(z::Complex{<:AbstractFloat}, n::Bool) = n ? z : one(z)  # to resolve ambiguity
^(z::Complex{<:Integer}, n::Bool) = n ? z : one(z)        # to resolve ambiguity

^(z::Complex{<:AbstractFloat}, n::Integer) =
    n>=0 ? power_by_squaring(z,n) : power_by_squaring(inv(z),-n)
^(z::Complex{<:Integer}, n::Integer) = power_by_squaring(z,n) # DomainError for n<0

function ^(z::Complex{T}, p::S) where {T<:Real,S<:Real}
    P = promote_type(T,S)
    return Complex{P}(z) ^ P(p)
end
function ^(z::T, p::Complex{S}) where {T<:Real,S<:Real}
    P = promote_type(T,S)
    return P(z) ^ Complex{P}(p)
end

function sin(z::Complex{T}) where T
    F = float(T)
    zr, zi = reim(z)
    if zr == 0
        Complex(F(zr), sinh(zi))
    elseif !isfinite(zr)
        if zi == 0 || isinf(zi)
            Complex(F(NaN), F(zi))
        else
            Complex(F(NaN), F(NaN))
        end
    else
        s, c = sincos(zr)
        Complex(s * cosh(zi), c * sinh(zi))
    end
end


function cos(z::Complex{T}) where T
    F = float(T)
    zr, zi = reim(z)
    if zr == 0
        Complex(cosh(zi), isnan(zi) ? F(zr) : -flipsign(F(zr),zi))
    elseif !isfinite(zr)
        if zi == 0
            Complex(F(NaN), isnan(zr) ? zero(F) : -flipsign(F(zi),zr))
        elseif isinf(zi)
            Complex(F(Inf), F(NaN))
        else
            Complex(F(NaN), F(NaN))
        end
    else
        s, c = sincos(zr)
        Complex(c * cosh(zi), -s * sinh(zi))
    end
end


function tan(z::Complex)
    zr, zi = reim(z)
    w = tanh(Complex(-zi, zr))
    Complex(imag(w), -real(w))
end

function asin(z::Complex)
    zr, zi = reim(z)
    if isinf(zr) && isinf(zi)
        return Complex(copysign(oftype(zr,pi)/4, zr),zi)
    elseif isnan(zi) && isinf(zr)
        return Complex(zi, oftype(zr, Inf))
    end
    ξ = zr == 0       ? zr :
        !isfinite(zr) ? oftype(zr,pi)/2 * sign(zr) :
        atan(zr, real(sqrt(1-z)*sqrt(1+z)))
    η = asinh(copysign(imag(sqrt(conj(1-z))*sqrt(1+z)), imag(z)))
    Complex(ξ,η)
end

function acos(z::Complex)
    z = float(z)
    zr, zi = reim(z)
    if isnan(zr)
        if isinf(zi) return Complex(zr, -zi)
        else         return Complex(zr, zr) end
    elseif isnan(zi)
        if isinf(zr) return Complex(zi, abs(zr))
        elseif zr==0 return Complex(oftype(zr,pi)/2, zi)
        else         return Complex(zi, zi) end
    elseif zr==zi==0
        return Complex(oftype(zr,pi)/2, -zi)
    elseif zr==Inf && zi===0.0
        return Complex(zi, -zr)
    elseif zr==-Inf && zi===-0.0
        return Complex(oftype(zi,pi), -zr)
    end
    ξ = 2*atan(real(sqrt(1-z)), real(sqrt(1+z)))
    η = asinh(imag(sqrt(conj(1+z))*sqrt(1-z)))
    if isinf(zr) && isinf(zi) ξ -= oftype(η,pi)/4 * sign(zr) end
    Complex(ξ,η)
end

function atan(z::Complex)
    w = atanh(Complex(-imag(z),real(z)))
    Complex(imag(w),-real(w))
end

function sinh(z::Complex)
    zr, zi = reim(z)
    w = sin(Complex(zi, zr))
    Complex(imag(w),real(w))
end

function cosh(z::Complex)
    zr, zi = reim(z)
    cos(Complex(zi,-zr))
end

function tanh(z::Complex{T}) where T
    z = float(z)
    Tf = float(T)
    Ω = prevfloat(typemax(Tf))
    ξ, η = reim(z)
    if isnan(ξ) && η==0 return Complex(ξ, η) end
    if 4*abs(ξ) > asinh(Ω) #Overflow?
        Complex(copysign(one(Tf),ξ),
                copysign(zero(Tf),η*(isfinite(η) ? sin(2*abs(η)) : one(η))))
    else
        t = tan(η)
        β = 1+t*t #sec(η)^2
        s = sinh(ξ)
        ρ = sqrt(1 + s*s) #cosh(ξ)
        if isinf(t)
            Complex(ρ/s,1/t)
        else
            Complex(β*ρ*s,t)/(1+β*s*s)
        end
    end
end

function asinh(z::Complex)
    w = asin(Complex(-imag(z),real(z)))
    Complex(imag(w),-real(w))
end

function acosh(z::Complex)
    zr, zi = reim(z)
    if isnan(zr) || isnan(zi)
        if isinf(zr) || isinf(zi)
            return Complex(oftype(zr, Inf), oftype(zi, NaN))
        else
            return Complex(oftype(zr, NaN), oftype(zi, NaN))
        end
    elseif zr==-Inf && zi===-0.0 #Edge case is wrong - WHY?
        return Complex(oftype(zr,Inf), oftype(zi, -pi))
    end
    ξ = asinh(real(sqrt(conj(z-1))*sqrt(z+1)))
    η = 2*atan(imag(sqrt(z-1)),real(sqrt(z+1)))
    if isinf(zr) && isinf(zi)
        η -= oftype(η,pi)/4 * sign(zi) * sign(zr)
    end
    Complex(ξ, η)
end

function atanh(z::Complex{T}) where T
    z = float(z)
    Tf = float(T)
    x, y = reim(z)
    ax = abs(x)
    ay = abs(y)
    θ = sqrt(floatmax(Tf))/4
    if ax > θ || ay > θ #Prevent overflow
        if isnan(y)
            if isinf(x)
                return Complex(copysign(zero(x),x), y)
            else
                return Complex(real(inv(z)), y)
            end
        end
        if isinf(y)
            return Complex(copysign(zero(x),x), copysign(oftype(y,pi)/2, y))
        end
        return Complex(real(inv(z)), copysign(oftype(y,pi)/2, y))
    end
    β = copysign(one(Tf), x)
    z *= β
    x, y = reim(z)
    if x == 1
        if y == 0
            ξ = oftype(x, Inf)
            η = y
        else
            ξ = log(sqrt(sqrt(muladd(y, y, 4)))/sqrt(ay))
            η = copysign(oftype(y,pi)/2 + atan(ay/2), y)/2
        end
    else #Normal case
        ysq = ay^2
        if x == 0
            ξ = x
        else
            ξ = log1p(4x/(muladd(1-x, 1-x, ysq)))/4
        end
        η = angle(Complex((1-x)*(1+x)-ysq, 2y))/2
    end
    β * Complex(ξ, η)
end

#Rounding complex numbers
#Requires two different RoundingModes for the real and imaginary components
"""
    round(z::Complex[, RoundingModeReal, [RoundingModeImaginary]])
    round(z::Complex[, RoundingModeReal, [RoundingModeImaginary]]; digits=0, base=10)
    round(z::Complex[, RoundingModeReal, [RoundingModeImaginary]]; sigdigits, base=10)

Return the nearest integral value of the same type as the complex-valued `z` to `z`,
breaking ties using the specified [`RoundingMode`](@ref)s. The first
[`RoundingMode`](@ref) is used for rounding the real components while the
second is used for rounding the imaginary components.


`RoundingModeReal` and `RoundingModeImaginary` default to [`RoundNearest`](@ref),
which rounds to the nearest integer, with ties (fractional values of 0.5)
being rounded to the nearest even integer.

# Examples
```jldoctest
julia> round(3.14 + 4.5im)
3.0 + 4.0im

julia> round(3.14 + 4.5im, RoundUp, RoundNearestTiesUp)
4.0 + 5.0im

julia> round(3.14159 + 4.512im; digits = 1)
3.1 + 4.5im

julia> round(3.14159 + 4.512im; sigdigits = 3)
3.14 + 4.51im
```
"""
function round(z::Complex, rr::RoundingMode=RoundNearest, ri::RoundingMode=rr; kwargs...)
    Complex(round(real(z), rr; kwargs...),
            round(imag(z), ri; kwargs...))
end


float(z::Complex{<:AbstractFloat}) = z
float(z::Complex) = Complex(float(real(z)), float(imag(z)))

big(::Type{Complex{T}}) where {T<:Real} = Complex{big(T)}
big(z::Complex{T}) where {T<:Real} = Complex{big(T)}(z)

## Array operations on complex numbers ##
"""
    complex(A::AbstractArray)

Return an array containing the complex analog of each entry in array `A`.

Equivalent to `complex.(A)`, except that the return value may share memory with all or
part of `A` in accordance with the behavior of `convert(T, A)` given output type `T`.

# Examples
```jldoctest
julia> complex([1, 2, 3])
3-element Vector{Complex{Int64}}:
 1 + 0im
 2 + 0im
 3 + 0im
```
"""
complex(A::AbstractArray{<:Complex}) = A

function complex(A::AbstractArray{T}) where T
    if !isconcretetype(T)
        error("`complex` not defined on abstractly-typed arrays; please convert to a more specific type")
    end
    convert(AbstractArray{typeof(complex(zero(T)))}, A)
end

## Machine epsilon for complex ##

eps(z::Complex{<:AbstractFloat}) = hypot(eps(real(z)), eps(imag(z)))

eps(::Type{Complex{T}}) where {T<:AbstractFloat} = sqrt(2*one(T))*eps(T)
