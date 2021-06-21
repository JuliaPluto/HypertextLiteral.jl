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

* Within a `<script>` tag and attributes starting with `on`, support
  translation of Julia objects to Javascript.

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
