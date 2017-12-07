export @set, @lens, @focus
"""
    @set assignment

Update deeply nested fields of an immutable object.
```jldoctest
julia> using Setfield

julia> struct T;a;b end

julia> t = T(1,2)
T(1, 2)

julia> @set t.a = 5
T(5, 2)

julia> @set t.a = T(2,2)
T(T(2, 2), 2)

julia> @set t.a.b = 3
T(T(2, 3), 2)
```
"""
macro set(ex)
    atset_impl(ex)
end

parse_obj_lenses(obj::Symbol) = esc(obj), ()

function parse_obj_lenses(ex::Expr)
    @assert ex.head isa Symbol
    if Meta.isexpr(ex, :ref)
        index = map(esc, ex.args[2:end])
        lens = Expr(:call, :IndexLens, index...)
    elseif Meta.isexpr(ex, :(.))
        @assert length(ex.args) == 2
        field = ex.args[2]
        lens = :(FieldLens{$field}())
    end
    obj, lenses_tail = parse_obj_lenses(ex.args[1])
    lenses = tuple(lens, lenses_tail...)
    obj, lenses
end

function parse_obj_lens(ex::Expr)
    obj, lenses = parse_obj_lenses(ex)
    lens = Expr(:call, :compose, lenses...)
    obj, lens
end

const UPDATE_OPERATOR_TABLE = Dict(
:(+=) => +,
:(-=) => -,
:(*=) => *,
)

struct _UpdateOp{OP,V}
    op::OP
    val::V
end
(u::_UpdateOp)(x) = u.op(x, u.val)

function atset_impl(ex::Expr)
    @assert ex.head isa Symbol
    @assert length(ex.args) == 2
    ref, val = ex.args
    obj, lens = parse_obj_lens(ref)
    val = esc(val)
    ret = if ex.head == :(=)
        quote
            lens = $lens
            $obj = set(lens, $obj, $val)
        end
    else
        op = UPDATE_OPERATOR_TABLE[ex.head]
        f = :(_UpdateOp($op,$val))
        :($obj = update($f, $lens, $obj))
    end
    ret
end

macro lens(ex)
    obj, lens = parse_obj_lens(ex)
    lens
end

macro focus(ex)
    obj, lens = parse_obj_lens(ex)
    quote
        object = $obj
        lens = $lens
        Focused(object, lens)
    end
end

print_application(io::IO, l::FieldLens{field}) where {field} = print(io, ".", field)
print_application(io::IO, l::IndexLens) = print(io, "[", join(l.indices, ", "), "]")
function print_application(io::IO, l::ComposedLens)
    print_application(io, l.lens2)
    print_application(io, l.lens1)
end

function Base.show(io::IO, l::Lens)
    print(io, "(@lens _")
    print_application(io, l)
    print(io, ')')
end

function show_generic(io::IO, args...)
    types = map(typeof, tuple(io, args...))
    Types = Tuple{types...}
    invoke(show, Types, io, args...)
end
show_generic(args...) = show_generic(STDOUT, args...)
