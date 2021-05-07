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

Any datatype can be enhanced to work directly with this and similar
libraries by implementing `show` for `"text/html"`. In this case,
properly escaping content is important.

    struct Showable data::String end

    function Base.show(io::IO, mime::MIME"text/html", c::Showable)
        value = replace(replace(c.data, "&"=>"&amp;"), "<"=>"&lt;")
        print(io, "<showable>$(value)</showable>")
    end

    @print @htl("<span>$(Showable("a&b"))</span>")
    #-> <span><showable>a&amp;b</showable></span>

If the type of a value is not `showable` as `"text/html"`, a function is
generated that prints the value, escapes the output, placed inside a
`<span>` tag using the type's name as the `class` attribute.

    struct Custom data::String; end

    Base.print(io::IO, c::Custom) = print(io, c.data)

    @print @htl("<div>$(Custom("a&b"))</div>")
    #-> <div><span class="Custom">a&amp;b</span></div>

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

This is essentially what `@htl` macro produces.

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

Like `content` above, `Bypass` and `Reprint` work identically.

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
    struct Custom data::String end

    function Base.show(io::IO, mime::MIME"text/javascript", c::Custom)
        print(io, c)
    end

There is a small ecosystem of methods to implement the expansion of
`Dict`, `Pair`, `NamedTuple`, `Vector`, `Tuple` and `Base.Generator` in
multiple contexts. They could be reused or just ignored.

## Script Context

Within the `script` tag, content is not `"text/html"`, instead, it is
treated as `"text/javascript"`. Custom objects which are `showable` as
`"text/javascript"` can be printed without any escaping in this context.

    struct Log
        data
    end

    function Base.show(io::IO, mime::MIME"text/javascript", c::Log)
        print(io, "console.log(", c.data, ")")
    end

    @print @htl("""<script>$(Log("undefined"))</script>""")
    #-> <script>console.log(undefined)</script>

Alternatively, one could implement `print_script` to provide a
representation for this context.

    import HypertextLiteral: print_script

    function print_script(io::IO, c::Log)
        print(io, "console.log(")
        print_script(io, c.data)
        print(io, ")")
    end

    @print @htl("""<script>$(Log(nothing))</script>""")
    #-> <script>console.log(undefined)</script>

This content must not only be valid Javascript, but also escaped so that
`<script>`, `</script>`, and `<!--` literal values do not appear. When
using `print_script` this work is performed automatically.

    content = """<script>alert("hello")</script>"""

    @print @htl("<script>$(Log(content))</script>")
    #-> <script>console.log("<\script>alert(\"hello\")<\/script>")</script>
