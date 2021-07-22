# `htl` String Literal

This package additionally provides the `@htl_str` non-standard string
literal.

    using HypertextLiteral

    name = "World"

    htl"<span>Hello $name</span>"
    #-> <span>Hello World</span>

    @htl_str "<span>Hello \$name</span>"
    #-> <span>Hello World</span>

## Notable Differences

Unlike `@htl`, the `htl` string literal uses `@raw_str` escaping rules.
So long as a double-quote character does not come before a slash, the
slash itself need not be escaped.

    htl"<span>\some\path</span>"
    #-> <span>\some\path</span>

In this notation, `\"` can be used to escape a double quote. However,
other escape sequences are not expanded.

    htl"Hello\"\nWorld\""
    #-> Hello"\nWorld"

As a special case, the dollar-sign (`$`) can be escaped by doubling.

    amount = 42

    htl"<span>They paid $$$amount</span>"
    #-> <span>They paid $42</span>

Alternatively, one can use the HTML character entity `#&36;`.

    htl"<span>They paid &#36;$amount</span>"
    #-> <span>They paid &#36;42</span>

Unlike the `@htl` macro, nesting doesn't work.

    htl"Hello $(htl"World")"
    #-> ERROR: syntax: cannot juxtapose string literal

Triple double-quoted syntax can be used in this case.

    htl"""Hello $(htl"World")"""
    #-> Hello World

However, this trick works only one level deep. Hence, there are some
significant downsides to using this format, which are explored in detail
at Julia #38948.

## Dynamic Templates

The `@htl_str` macro can be used to dynamically construct templates.
Suppose you have a schema that is provided dynamically. Let's make a
test database with exactly one row.

    T = NamedTuple{(:idx, :value), Tuple{Int64, String}};

    database = [T((1, "A&B"))];

    display(database)
    #=>
    1-element Vector{NamedTuple{(:idx, :value), …}:
     (idx = 1, value = "A&B")
    =#

We could construct a table header from this schema.

    fields = T.parameters[1]
    #-> (:idx, :value)

    head = @htl "<tr>$([@htl("<th>$x") for x in fields])"
    #-> <tr><th>idx<th>value

Then, we need to compute a template for each row.

    row_template = "<tr>$(join(["<td>\$(row[$(repr(x))])" for x in fields]))"

    print(row_template)
    #-> <tr><td>$(row[:idx])<td>$(row[:value])

Using `eval` with `@htl_str` we could construct our template function.

    eval(:(tablerow(row) = @htl_str $row_template))

    tablerow(database[1])
    #-> <tr><td>1<td>A&amp;B

A template for the entire table could be constructed.

    table_template = "<table>$head\$([tablerow(row) for row in data])</table>"

    print(table_template)
    #-> <table><tr><th>idx…$([tablerow(row) for row in data])</table>

    eval(:(print_table(data) = @htl_str $table_template))

Then, finally, this could be used.

    print_table(database)
    #-> <table><tr><th>idx<th>value<tr><td>1<td>A&amp;B</table>

## Regression Tests & Notes

Due to `@raw_str` escaping, string literal forms are a bit quirky. Use
the triple double-quoted form if your content has a double quote. Avoid
slashes preceding a double quote, instead use the `&#47;` HTML entity.

    htl"\"\t\\"
    #-> "\t\

    htl"(\\\")"
    #-> (\")

Even though we could permit interpretation of arrays notation, we stick
with keeping this an error for consistency with the macro form.

    htl"$[1,2,3]"
    #=>
    ERROR: LoadError: DomainError with [1, 2, 3]:
    interpolations must be symbols or parenthesized⋮
    =#

Let's also not permit top-level assignments.

    htl"$(k=value)"
    #=>
    ERROR: LoadError: DomainError with k = value:
    assignments are not permitted in an interpolation⋮
    =#

Since the implementers of the notation have some control over the
parsing, we can reliably detect string literals (Julia #38501).

    htl"""<span>$("A&B")</span>"""
    #-> <span>A&amp;B</span>

There is one less round of parenthesis needed for tuples, named tuples
and generators (Julia #38734).

    name = "Hello"

    htl"<tag $(user=name,)/>"
    #-> <tag user='Hello'/>

    print(htl"<span>$(n for n in 1:3)</span>")
    #-> <span>123</span>

Due to escaping rules, we interpret a dollar sign as beginning an
expression, even if it might otherwise be preceded by a slash.

    htl"Hello\$#"
    #=>
    ERROR: LoadError: "missing expression at 7: #"⋮
    =#
