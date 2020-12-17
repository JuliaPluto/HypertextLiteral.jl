## Integration

For hypertext content, Julia has a protocol to let independent libraries
work together. For any object, one could ask if it is `showable` to
displays supporting the `"text/html"` mimetype.

    using HypertextLiteral

    macro print(expr)
        :(display("text/html", $expr))
    end

    showable("text/html", @htl("<tag/>"))
    #-> true

We use this protocol to integrate with third party tools, such as
`Hyperscript` without introducing dependencies.

    using Hyperscript
    @tags span div

    @print component = span("...")
    #-> <span>...</span>

Since `component` is showable via `"text/html"`, it can be integrated
directly. Conversely, results of `@htl` interpolation can be included
directly as a Hyperscript node.

    @print @htl("<div>$(span("..."))</div>")
    #-> <div><span>...</span></div>

    @print div(@htl("<span>...</span>"))
    #-> <div><span>...</span></div>

Generally, any custom component can be enhanced to work directly with
this and similar libraries by implementing `show` for `"text/html"`.
In this case, properly escaping content is important.

    struct Custom data::String end

    function Base.show(io::IO, mime::MIME"text/html", c::Custom)
        value = replace(replace(c.data, "&"=>"&amp;"), "<"=>"&lt;")
        print(io, "<custom>$(value)</custom>")
    end

    @print @htl("<span>$(Custom("a&b"))</span>")
    #-> <span><custom>a&amp;b</custom></span>

Conservatively, many more characters should be escaped, including both
single (`'`) and double (`"`) quotes. However, we shouldn't assume this.

## Content Extensions

Sometimes it's useful to extend `@htl` so that it knows how to print
your object without implementing `show` for `"text/html"` this can be
done by implementing a method for the `content()` function.

    struct Custom data::String end

    HypertextLiteral.content(c::Custom) = "They said: '$(c.data)'"

    @print @htl("<span>$(Custom("Hello"))</span>")
    #-> <span>They said: &apos;Hello&apos;</span>

By default, the result of the `content()` is fully escaped, in this way
you don't have to worry about implement one's own escaping. If your
custom object is building tagged content, you can bypass escaping.

    HypertextLiteral.content(c::Custom) =
        HypertextLiteral.Bypass("<span>$(c.data)</span>")

    @print @htl("<div>$(Custom("Hello"))</div>")
    #-> <div><span>Hello</span></div>

Unfortunately, this won't encode the argument to your object.

    @print @htl("<div>$(Custom("<script>alert('whoops!);"))</div>")
    #-> <div><span><script>alert('whoops!);</span></div>

This can be addressed with `Reprint`. In this case, the value you return
is a functor (and object holding a function) built by `Reprint`.

    using HypertextLiteral: Bypass, Reprint

    HypertextLiteral.content(c::Custom) =
        Reprint(io::IO -> begin
            print(io, Bypass("<span>"))
            print(io, c.data)
            print(io, Bypass("</span>"))
        end)

    @print @htl("<div>$(Custom("a&b"))</div>")
    #-> <div><span>a&amp;b</span></div>

Once you go though all this work though, you could simply use `@htl`.

    HypertextLiteral.content(c::Custom) =
        @htl("<span>$(c.data)</span>")

    @print @htl("<div>$(Custom("a&b"))</div>")
    #-> <div><span>a&amp;b</span></div>

## Attribute Value Context

Unlike `content` which has a `show` `"text/html"` fallback, there is no
such protocol for attribute values, which have different escaping needs
(single or double quote, respectively). Hence, integrating
`Hyperscript`'s CSS `Unit` object, such as `2em`, isn't automatic. By
default, a `MethodError` is raised.

    typeof(2em)
    #-> Hyperscript.Unit{:em, Int64}

    @print @htl("<div style=$((border=2em,))>...</div>")
    #-> …ERROR: MethodError: no method matching attribute_value(…Unit{:em,⋮

Letting objects of an unknown type work with `@htl` macros follows
Julia's sensibilities, you implement `attribute_value` for that type.

    HypertextLiteral.attribute_value(x::Hyperscript.Unit) = x

    @print @htl("<div style=$((border=2em,))>...</div>")
    #-> <div style='border: 2em;'>...</div>

This works as follows. When `obj` is encountered in an attribute
context, `attribute_value(obj)` is called. Then, `print()` is called on
the result to create a character stream. This stream is then escaped and
included into the results. Let's do this with a `Custom` object.

    struct Custom data::String end

    HypertextLiteral.attribute_value(x::Custom) = x.data

    @print @htl("<tag attribute=$(Custom("'A&B'"))/>")
    #-> <tag attribute='&apos;A&amp;B&apos;'/>

Like `content` above, `Bypass` and `Reprint` work identically. That
said, nested `@htl` macros will not work (they assume element content is
the output). For more complicated `attribute_value` plugins, directly
constructing the escaping pipeline is needed.

## Inside Tag Context

In some important cases one wishes to expand a `Julia` object into a set
of attributes. This can be done by implementing `insidetag()`. At this
point, it's better to study the implementation in `convert.jl`. Here is
an example.

    using HypertextLiteral: attribute_pair

    struct CustomCSS class::Vector{Symbol}; style end

    HypertextLiteral.inside_tag(s::CustomCSS) = begin
        myclass = join((string(x) for x in s.class), " ")
        Reprint() do io::IO
            print(io, attribute_pair(:class, myclass))
            print(io, attribute_pair(:style, s.style))
        end
    end

    style = CustomCSS([:one, :two], :background_color => "#92a8d1")

    @print @htl("<div $style>Hello</div>")
    #-> <div class='one two' style='background-color: #92a8d1;'>Hello</div>

There is a small ecosystem of methods to implement the expansion of
`Dict`, `Pair`, `NamedTuple`, `Vector`, `Tuple` and `Base.Generator` in
multiple contexts. They could be reused or just ignored.
