# Attributes & Style

Interpolation within single and double quoted attribute values are
supported. Regardless of context, all four characters, `<`, `&`, `'`,
and `"` are escaped.

    using HypertextLiteral

    qval = "\"&'"

    @htl("""<tag double="$qval" single='$qval' />""")
    #-> <tag double="&quot;&amp;&apos;" single='&quot;&amp;&apos;' />

Unquoted or bare attributes are also supported. These are serialized
using the single quoted style so that spaces and other characters do not
need to be escaped.

    arg = "book='Strunk & White'"

    @htl("<tag bare=$arg />")
    #-> <tag bare='book=&apos;Strunk &amp; White&apos;' />

In this document, we discuss interpolation within attribute values.

## Boolean Attributes

Within bare attributes, boolean values provide special support for
boolean HTML properties, such as `"disabled"`. When a value is `false`,
the attribute is removed. When the value is `true` then the attribute is
kept, with value being an empty string (`''`).

    @htl("<button disabled=$(true)>Disabled</button>")
    #-> <button disabled=''>Disabled</button>

    @htl("<button disabled=$(false)>Clickable</button>")
    #-> <button>Clickable</button>

Within a quoted attribute, boolean values are printed as-is.

    @htl("<input type='text' value='$(true)'>")
    #-> <input type='text' value='true'>

    @htl("<input type='text' value='$(false)'>")
    #-> <input type='text' value='false'>

## Nothing

Within bare attributes, `nothing` is treated as `false`, and the
attribute is removed.

    @htl("<button disabled=$(nothing)>Clickable</button>")
    #-> <button>Clickable</button>

Within quoted attributes, `nothing` is treated as the empty string.

    @htl("<input type='text' value='$(nothing)'>")
    #-> <input type='text' value=''>

This is designed for consistency with `nothing` within element content.

## Vectors

Vectors and tuples are flattened using the space as a separator.

    class = ["text-center", "text-left"]

    @htl("<div class=$class>...</div>")
    #-> <div class='text-center text-left'>...</div>

    @htl("<div class='$class'>...</div>")
    #-> <div class='text-center text-left'>...</div>

    @htl("<tag att=$([:one, [:two, "three"]])/>")
    #-> <tag att='one two three'/>

    @htl("<tag att='$((:one, (:two, "three")))'/>")
    #-> <tag att='one two three'/>

This behavior supports attributes having name tokens, such as Cascading
Style Sheets' `"class"`.

## Pairs & Dictionaries

Pairs, named tuples, and dictionaries are given treatment to support
attributes such as CSS's `"style"`.

    style = Dict(:padding_left => "2em", :width => "20px")

    @htl("<div style=$style>...</div>")
    #-> <div style='padding-left: 2em; width: 20px;'>...</div>

    @htl("<div style='font-size: 25px; $(:padding_left=>"2em")'/>")
    #-> <div style='font-size: 25px; padding-left: 2em;'/>

    @htl("<div style=$((padding_left="2em", width="20px"))/>")
    #-> <div style='padding-left: 2em; width: 20px;'/>

For each pair, keys are separated from their value with a colon (`:`).
Adjacent pairs are delimited by the semi-colon (`;`). Moreover, for
`Symbol` keys, `snake_case` values are converted to `kebab-case`.

## General Case

Beyond these rules for booleans, `nothing`, and collections, values
are reproduced with their `print` representation.

    @htl("<div att=$((:a_symbol, "string", 42, 3.1415))/>")
    #-> <div att='a_symbol string 42 3.1415'/>

This permits the serialization of all sorts of third party objects.

    using Hyperscript

    typeof(2em)
    #-> Hyperscript.Unit{:em, Int64}

    @htl "<div style=$((border=2em,))>...</div>"
    #-> <div style='border: 2em;'>...</div>

## Extensions

Often times the default print representation of a custom type isn't
desirable for use inside an attribute value.

    struct Custom data::String end

    @htl "<tag att=$(Custom("A&B"))/>"
    #-> <tag att='…Custom(&quot;A&amp;B&quot;)'/>

This can be sometimes addressed by implementing `Base.print()`.

    Base.print(io::IO, c::Custom) = print(io, c.data)

    print(@htl "<tag att=$(Custom("A&B"))/>")
    #-> <tag att='A&amp;B'/>

However, sometimes this isn't possible or desirable. A tailored
representation specifically for use within an `attribute_value` can be
provided.

    HypertextLiteral.attribute_value(x::Custom) = x.data

    @htl "<tag att=$(Custom("A&B"))/>"
    #-> <tag att='A&amp;B'/>

Like `content` extensions, `Bypass` and `Reprint` work identically.

## Inside a Tag

Attributes may also be provided by any combination of dictionaries,
named tuples, and pairs. Attribute names are normalized, where
`snake_case` becomes `kebab-case`. We do not convert `camelCase` due to
XML (MathML and SVG) attribute case sensitivity. Moreover, `String`
attribute names are passed along as-is.

    attributes = Dict(:data_style => :green, "data_value" => 42, )

    @htl("<div $attributes/>")
    #-> <div data-style='green' data_value='42'/>

    @htl("<div $(:data_style=>:green) $(:dataValue=>42)/>")
    #-> <div data-style='green' dataValue='42'/>

    @htl("<div $((:data_style=>:green, "data_value"=>42))/>")
    #-> <div data-style='green' data_value='42'/>

    @htl("<div $((data_style=:green, dataValue=42))/>")
    #-> <div data-style='green' dataValue='42'/>

A `Pair` inside a tag is treated as an attribute.

    @htl "<div $(:data_style => "green")/>"
    #-> <div data-style='green'/>

A `Symbol` or `String` inside a tag is an empty attribute.

    @htl "<div $(:data_style)/>"
    #-> <div data-style=''/>

    #? VERSION >= v"1.6.0-DEV"
    @htl "<div $("data_style")/>"
    #-> <div data_style=''/>

To expand an object into a set of attributes, implement `inside_tag()`.
For example, let's suppose we have an object that represents both a list
of CSS classes and a custom style.

    using HypertextLiteral: attribute_pair, Reprint

    struct CustomCSS class::Vector{Symbol}; style end

    HypertextLiteral.inside_tag(s::CustomCSS) = begin
        myclass = join((string(x) for x in s.class), " ")
        Reprint() do io::IO
            print(io, attribute_pair(:class, myclass))
            print(io, attribute_pair(:style, s.style))
        end
    end

    style = CustomCSS([:one, :two], :background_color => "#92a8d1")

    print(@htl "<div $style>Hello</div>")
    #-> <div class='one two' style='background-color: #92a8d1;'>Hello</div>

## Style Tag

Within a `<style>` tag, Julia values are interpolated using the same
rules as they would be if they were encountered within an attribute
value, only that ampersand escaping is not done.

    style = Dict(:padding_left => "2em", :width => "20px")

    @htl """<style>span {$style}</style>"""
    #-> <style>span {padding-left: 2em; width: 20px;}</style>

In this context, content is validated to ensure it doesn't contain
`"</style>"`.

    expr = """<style>span {display: inline;}</style>"""

    @htl "<style>$expr</style>"
    #-> …ERROR: "Content within a style tag must not contain `</style>`"⋮

## Edge Cases

Attribute names should be non-empty and not in a list of excluded
characters.

    @htl "<tag $("" => "value")/>"
    #-> ERROR: LoadError: "Attribute name must not be empty."⋮

    @htl "<tag $("&att" => "value")/>"
    #=>
    ERROR: LoadError: DomainError with &att:
    Invalid character ('&') found within an attribute name.⋮
    =#

We don't permit adjacent unquoted attribute values.

    @htl("<tag bare=$(true)$(:invalid)")
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

Unquoted interpolation adjacent to a raw string is also an error.

    @htl("<tag bare=literal$(:invalid)")
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

    @htl("<tag bare=$(invalid)literal")
    #=>
    ERROR: LoadError: DomainError with bare=literal:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

Ensure that dictionary style objects are serialized. See issue #7.

    let
        h = @htl("<div style=$(Dict("color" => "red"))>asdf</div>")
        repr(MIME"text/html"(), h)
    end
    #-> "<div style='color: red;'>asdf</div>"

Let's ensure that attribute values in a dictionary are escaped.

    @htl "<tag escaped=$(Dict(:esc=>"'&\"<"))/>"
    #-> <tag escaped='esc: &apos;&amp;&quot;&lt;;'/>

When we normalize attribute names, we strip leading underscores.

    @htl "<tag $(:__att => :value)/>"
    #-> <tag att='value'/>

We don't expand into attributes things that don't look like attributes.

    @htl "<tag $(3)/>"
    #-> ERROR: MethodError: no method matching inside_tag(::Int64)⋮

One can add additional attributes following a bare name.

    @htl "<tag bing $(:att)/>"
    #-> <tag bing att=''/>

Inside a tag, tuples can have many kinds of pairs.

    a1 = "a1"
    @htl "<tag $((a1,:a2,:a3=3,a4=4))/>"
    #-> <tag a1='' a2='' a3='3' a4='4'/>

The macro attempts to expand attributes inside a tag. To ensure the
runtime dispatch also works, let's do a few things once indirect.

    hello = "Hello"
    defer(x) = x

    @htl "<tag $(defer(:att => hello))/>"
    #-> <tag att='Hello'/>

    @htl "<tag $(defer((att=hello,)))/>"
    #-> <tag att='Hello'/>

    @htl "<tag $(:att => defer(hello))/>"
    #-> <tag att='Hello'/>

    @htl "<tag $(defer(:att) => hello)/>"
    #-> <tag att='Hello'/>

It's a lexing error to have an attribute lacking a name.

    @htl "<tag =value/>"
    #=>
    ERROR: LoadError: DomainError with  =value/>:
    unexpected equals sign before attribute name⋮
    =#

It's a lexing error to have an attribute lacking a value.

    @htl "<tag att=>"
    #=>
    ERROR: LoadError: DomainError with =>:
    missing attribute value⋮
    =#

Attribute names and values can be spaced out.

    @htl "<tag one two = value />"
    #-> <tag one two = value />

Invalid attribute names are reported.

    @htl "<tag at<ribute='val'/>"
    #=>
    ERROR: LoadError: DomainError with t<ribute=…
    unexpected character in attribute name⋮
    =#

While assignment operator is permitted in Julia string interpolation, we
exclude it to guard it against accidently forgetting a comma.

    @htl "<div $((data_value=42,))/>"
    #-> <div data-value='42'/>

    @htl("<div $((data_value=42))/>")
    #=>
    ERROR: LoadError: DomainError with data_value = 42:
    assignments are not permitted in an interpolation⋮
    =#

    @htl("<div $(data_value=42)/>")
    #=>
    ERROR: LoadError: DomainError with data_value = 42:
    assignments are not permitted in an interpolation⋮
    =#
