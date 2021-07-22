# Design Rationale

This package is implemented according to several design criteria.

* Operation of interpolated expressions (`$`) should (mostly) mirror
  what they would do with regular Julia strings, updated with hypertext
  escaping sensibilities including proper escaping.

* Speed of construction is critically important. This library is
  intended to be used deep within systems that generate extensive
  number of very large reports, interactively or in batch.

* With exception of boolean attributes (which must be removed to be
  false), templates are treated as-is and not otherwise modified.

* Within `<script>`, support translation of Julia objects to JavaScript.
  Enable this translation to be used within `on` and other contexts via
  `HypertextLiteral.js` function.

* Since the `style` and `class` attributes are so important in HTML
  construction, interpretations of Julia constructs should support
  these CSS attributes.

* There should be a discoverable and well documented extension API that
  permits custom data types to provide their own serialization
  strategies based upon syntactical context.

* As much processing (e.g. hypertext lexical analysis) should be done
  during macro expansion to reduce runtime and to report errors early.
  We'll be slightly slower on interactive use to be fast in batch.

* Full coverage of HTML syntax or reporting syntax or semantic errors
  within the HTML content is not a goal.

## Specific Design Decisions

Besides implementing `show`, we also provide serialization when printing
to `"text/html"` mime types.

    using HypertextLiteral

    @htl "<span>Hello World</span>"
    #-> <span>Hello World</span>

    display("text/html", @htl "<span>Hello World</span>")
    #-> <span>Hello World</span>

We wrap `missing` and other data types using a `<span>` tag as they are
printed. This permits customized CSS to control their presentation.

    @htl "<tag>$(missing)</tag>"
    #-> <tag><span class="Base-Missing">missing</span></tag>

Julia's regular interpolation stringifies everything. Instead, we treat
a `Vector` as a sequence to be concatenated. Within attributes, vectors
are space separated.

    @htl "$([x for x in 1:3])"
    #-> 123

    @htl "<tag att=$([x for x in 1:3])/>"
    #-> <tag att='1 2 3'/>

We treat `nothing` as being empty. This is true for both element content
and attribute values.

    @htl "<span>$(nothing)</span>"
    #-> <span></span>

    @htl "<tag att='$(nothing)'/>"
    #-> <tag att=''/>

## Notable Features

Attributes assigned a boolean value have specialized support.

    @htl "<input type='checkbox' selected=$(false) disabled=$(true)></input>"
    #-> <input type='checkbox' disabled=''></input>

Dictionaries are translated to support CSS within attributes and the
`<style>` tag. In this case, `snake_case` symbols become `kebab-case`.

    style = Dict(:padding_left => "2em", :width => "20px")

    @htl("<div style='font-size: 25px; $style'>...</div>")
    #-> <div style='font-size: 25px; padding-left: 2em; width: 20px;'>...</div>

    @htl "<style>input {$style}</style>"
    #-> <style>input {padding-left: 2em; width: 20px;}</style>

Within a `<script>` tag these macros provide a translation to Javascript.

    v = "<1 Brown \"M&M's\"!";

    @htl "<script>v = $v</script>"
    #-> <script>v = "<1 Brown \"M&M's\"!"</script>

JavaScript translation can be accessed via the `js` function.

    using HypertextLiteral: js

    @htl "<button onclick='alert($(js("M&M's")))'>"
    #-> <button onclick='alert(&quot;M&amp;M&apos;s&quot;)'>

The `@htl_str` form is useful for dynamically constructed templates.

    templ = join("<td>\$$x</td>" for x in [:a,:b])
    #-> "<td>\$a</td><td>\$b</td>"

    (a, b) = (:A, :B);

    eval(:(@htl_str($templ)))
    #-> <td>A</td><td>B</td>

Within element content, most datatypes are serialized within a `<span>` tag.

    using Dates

    @htl("<div>$(Date("2021-07-28"))</div>")
    #-> <div><span class="Dates-Date">2021-07-28</span></div>

This automatic wrapping permits CSS to be used to style output.
For example, the following style will display `missing` as `"N/A"`.

```HTML
    <style>
    span.Base-Missing {visibility: collapse;}
    span.Base-Missing::before {content: "N/A"; visibility: visible;}
    </style>
```

## Lexer Tests

There are several HTML syntax errors that we can detect as part of our
parser. For example, you shouldn't put comments within a script tag.

    @htl("<script><!-- comment --></script>")
    #-> ERROR: LoadError: "script escape or comment is not implemented"⋮

Our lexer currently doesn't bother with processor instructions or
doctype declarations. You could prepend these before your content.

    @htl("<?xml version='1.0'?>")
    #=>
    ERROR: LoadError: DomainError with <?xml ver…:
    unexpected question mark instead of tag name⋮
    =#

    @htl("<!DOCTYPE html>")
    #-> ERROR: LoadError: "DOCTYPE not supported"⋮

    @htl("<![CDATA[No <b>CDATA</b> either.]]>")
    #-> ERROR: LoadError: "CDATA not supported"⋮

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

Tags can be ended using SGML ending.

    @htl "<tag></>"
    #-> <tag></>

We add an extra space to ensure adjacent values parse properly.

    @htl "<tag $((:one))two=''/>"
    #-> <tag one='' two=''/>

    @htl "<tag $((:one))$((:two))/>"
    #-> <tag one='' two=''/>

Attribute names and values can be spaced out.

    @htl "<tag one two = value />"
    #-> <tag one two = value />

Invalid attribute names are reported.

    @htl "<tag at<ribute='val'/>"
    #=>
    ERROR: LoadError: DomainError with t<ribute=…
    unexpected character in attribute name⋮
    =#

Rawtext has a few interesting lexical cases.

    @htl """<style> </s </> </style>"""
    #-> <style> </s </> </style>

    @htl "<style> </s </style/"
    #=>
    ERROR: LoadError: DomainError with e/:
    unexpected solidus in tag⋮
    =#

    @htl "<style></style <"
    #=>
    ERROR: LoadError: DomainError with  <:
    unexpected character in attribute name⋮
    =#

Comments can contain interpolated values.

    content = "<!-- a&b -->"

    @htl "<!-- $content -->"
    #-> <!-- &lt;!-- a&amp;b --> -->

Empty comments are permitted.

    @htl "<!---->"
    #-> <!---->

Comments should not exist within a script tag.

    @htl("<script><!-- comment --></script>")
    #-> ERROR: LoadError: "script escape or comment is not implemented"⋮

Comments need to be well formed.

    @htl "<!-> "
    #=>
    ERROR: LoadError: DomainError with !-> :
    incorrectly opened comment⋮
    =#

    @htl "<!--> "
    #=>
    ERROR: LoadError: DomainError with -> :
    abrupt closing of empty comment⋮
    =#

    @htl "<!---> "
    #=>
    ERROR: LoadError: DomainError with -> :
    abrupt closing of empty comment⋮
    =#

Comments cannot contain a nested comment.

    @htl "<!-- <!-- nested --> -->"
    #=>
    ERROR: LoadError: DomainError with - nested …:
    nested comment⋮
    =#

Comments can contain content that is similar to a comment block, but
the recognition of these valid states is rather involved.

    @htl "<!-- <!-->"
    #-> <!-- <!-->

    @htl "<!--<x-->"
    #-> <!--<x-->

    @htl "<!--<!x!>-->"
    #-> <!--<!x!>-->

    @htl "<!--<!-x-->"
    #-> <!--<!-x-->

    @htl "<!---x-->"
    #-> <!---x-->

    @htl "<!--<<x-->"
    #-> <!--<<x-->

    @htl "<!-- - --! --- --!- -->"
    #-> <!-- - --! --- --!- -->

Not so sure about this lexical production... perhaps it's a
transcription error from the specification?

    @htl "<!----!>"
    #=>
    ERROR: LoadError: DomainError with !>:
    nested comment⋮
    =#

Even though actual content may be permitted in these odd spots, we don't
generally permit interpolation.

    @htl "<!--<$(:x)"
    #=>
    ERROR: LoadError: "unexpected binding STATE_COMMENT_LESS_THAN_SIGN"⋮
    =#

Of course, we could have pure content lacking interpolation, this also
goes though the lexer.

    @htl "<div>Hello<b>World</b>!</div>"
    #-> <div>Hello<b>World</b>!</div>

However, this macro requires a string literal.

    f() = "<div>Hello<b>World</b>!</div>"

    @htl f()
    #=>
    ERROR: LoadError: DomainError with f():
    a string literal is required⋮
    =#
