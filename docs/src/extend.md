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
In this case, properly escaping concent is important.

    struct Custom data::String end

    function Base.show(io::IO, mime::MIME"text/html", c::Custom)
        value = replace(replace(c.data, "&"=>"&amp;"), "<"=>"&lt;")
        print(io, "<custom>$(value)</custom>")
    end

    @print @htl("<span>$(Custom("a&b"))</span>")
    #-> <span><custom>a&amp;b</custom></span>

Conservatively, many more characters should be escaped, including both
single (`'`) and double (`"`) quotes. However, we shouldn't assume this.

## Attribute Value Context

Unfortunately, there is no such protocol for attribute values, which
have different escaping needs (single or double quote, respectively).
Hence, integrating `Hyperscript`'s CSS `Unit` object, such as `2em`,
isn't automatic. By default, a `MethodError` is raised.

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
context, `attribute_value(obj)` is called. Then, `print()` is called
on the result to create a character stream. This stream is then escaped
and included into the results. Let's do this with a `Custom` object.

    struct Custom data::String end

    HypertextLiteral.attribute_value(x::Custom) = x.data

    @print @htl("<tag attribute=$(Custom("'A&B'"))/>")
    #-> <tag attribute='&apos;A&amp;B&apos;'/>

## Content Context

TODO: Discuss `content` extensions.

## Inside Tag Context

TODO: Discuss `inside_tag` extensions.
