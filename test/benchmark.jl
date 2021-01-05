#!/usr/bin/env julia
using Faker, HypertextLiteral, Hyperscript, BenchmarkTools

# This is going to simulate a hierarchical report that lists a set of
# companies, and for each company, a list of employees.

Faker.seed(4321)

make_employee() = (
  first_name=Faker.first_name(),
  last_name=Faker.last_name(),
  title=Faker.job(),
  main_number=Faker.phone_number(),
  email=Faker.email(),
  cell_phone=Faker.cell_phone(),
  color= Faker.hex_color(),
  comments= Faker.paragraphs()
)

make_customer() = (
   company=Faker.company(),
   url=Faker.url(),
   phrase=Faker.catch_phrase(),
   active=Faker.date_time_this_decade(before_now=true, after_now=false),
   notes= Faker.sentence(number_words=rand(2:9), variable_nb_words=true),
   employees=[make_employee() for x in 1:rand(3:18)])

database = [make_customer() for x in 1:13]

htl_database(d) = @htl("
  <html>
    <head><title>Customers &amp; Employees)</title></head>
    <body>
    $((map(d) do c; htl_customer(c); end))</body>
  </html>
")

htl_customer(c) = @htl("
    <dl>
      <dt>Company<dd>$(c.company)
      <dt>Phrase<dd>$(c.phrase)
      <dt>Active Since<dd>$(c.active)
      <dt>Employees<dd>
        <table>
          <tr><th>Last Name<th>First Name<th>Title
              <th>E-Mail<th>Office Phone<th>Cell Phone
              <th>Comments</tr>
          $((map(c.employees) do e; htl_employee(e); end))</table>
    </dl>
")

htl_employee(e) = @htl("
      <tr><td>$(e.last_name)<td>$(e.first_name)<td>$(e.title)
          <td><a href='mailto:$(e.email)'>$(e.email)</a>
          <td>$(e.main_number)<td>$(e.cell_phone)
          <td>$((@htl("<span>$c</span>") for c in e.comments))
")

htl_test() = begin
   io = IOBuffer()
   ob = htl_database(database)
   show(io, MIME("text/html"), ob)
   return io
end

# very silly test using attributes rather than elements...

att_database(d) = htl"""
  <html>
    <head title=$("Customers & Employees")/>
    <body>
    $(map(d) do c; att_customer(c); end)
    </body>
  </html>
"""

att_customer(c) = @htl("""
    <div>
       <form>
         <label>Company</label><input value=$(c.company)>
         <label>Phrase</label><input value='$(c.phrase)'>
         <label>Active Since</label><input value="$(c.active)">
         <label>Employees</label>
       </form>
          $((map(c.employees) do e; att_employee(e); end))
    </div>
""")

att_employee(e) = @htl("""
       <form>
         <label>Last Name</label><input value=$(e.last_name)>
         <label>First Name</label><input value="$(e.first_name)">
         <label>Title</label><input value='$(e.title)'>
         <label>E-Mail</label><input $(:value => e.email)>
         <label>Main</label><input $("value" => e.main_number))>
         <label>Cell</label><input $((value=e.main_number,))>
         $((htl"<span $(value=x,)/>" for x in e.comments))
""")

att_test() = begin
   io = IOBuffer()
   ob = att_database(database)
   show(io, MIME("text/html"), ob)
   return io
end

ee(x) = replace(replace(x, "&" => "&amp;"), "<" => "&lt;")
ea(x) = replace(replace(x, "&" => "&amp;"), "'" => "&apos;")

reg_database(d) = """
  <html>
    <head><title>Customers & Employees</title></head>
    <body>
    $(join([reg_customer(c) for c in d]))
    </body>
  </html>
"""

reg_customer(c) = """
    <dl>
      <dt>Company<dd>$(ee(c.company))
      <dt>Phrase<dd>$(ee(c.phrase))
      <dt>Active Since<dd>$(ee(c.active))
      <dt>Employees<dd>
        <table>
          <tr><th>Last Name<th>First Name<th>Title
              <th>E-Mail<th>Office Phone<th>Cell Phone
              <th>Comments</tr>
          $(join([reg_employee(e) for e in c.employees]))
        </table>
    </dl>
"""

reg_employee(e) = """
      <tr><td>$(ee(e.last_name))<td>$(ee(e.first_name))<td>$(e.title)
          <td><a href='mailto:$(ea(e.email))'>$(ee(e.email))</a>
          <td>$(ee(e.main_number))<td>$(ee(e.cell_phone))
          <td>$(join(["<span>$(ee(c))</span>" for c in e.comments]))
"""

reg_test() = begin
   io = IOBuffer()
   ob = reg_database(database)
   show(io, ob)
   return io
end


@tags html head body title dl dt dd table tr th td span

hs_database(d) =
  html(head(title("Customers & Employees")),
    body([hs_customer(c) for c in d]...))

hs_customer(c)=
  dl(dt("Company"), dd(c.company),
     dt("Phrase"), dd(c.phrase),
     dt("Active Since"), dd(c.active),
     dt("Employees"), dd(
       table(tr(th("Last Name"),th("First Name"),th("Title"),
                th("E-Mail"),th("Office Phone"),th("Cell Phone"),
                th("Comments")),
          [hs_employee(e) for e in c.employees]...)))

hs_employee(e) = tr(td(e.last_name), td(e.first_name), td(e.title),
                    td(href="mailto:$(e.email)", e.email),
                    td(e.main_number), td(e.cell_phone),
                    td([span(c) for c in e.comments]...))

hs_test() = begin
   io = IOBuffer()
   ob = hs_database(database)
   show(io, MIME("text/html"), ob)
   return io
end

function H(xs...)
    HTML() do io
        for x in xs
            show(io, MIME"text/html"(), x)
        end
    end
end

function entity(str::AbstractString)
    @assert length(str) == 1
    entity(str[1])
end

entity(ch::Char) = "&#$(Int(ch));"

HE(x) = HTML(replace(x, r"[<&]" => entity))
HA(x) = HTML(replace(x, r"[<']" => entity))

#HE(x) = HTML(replace(replace(x, "&" => "&amp;"), "<" => "&lt;"))
#HA(x) = HTML(replace(replace(x, "&" => "&amp;"), "\"" => "&quot;"))

cus_database(d) =
   H(HTML("<html><head><title>"), HE("Customers & Employees"),
     HTML("</title></head><body>"),
      [cus_customer(c) for c in d]...,
      HTML("</body></html>"))

cus_customer(c) =
   H(HTML("<dl><dt>Company<dd>"), HE(c.company),
     HTML("<dt>Phrase<dd>"), HE(c.phrase),
     HTML("<dt>Active Siince<dd>"), HE(c.active),
     HTML("""
      <dt>Employees<dd>
        <table>
          <tr><th>Last Name<th>First Name<th>Title
              <th>E-Mail<th>Office Phone<th>Cell Phone
              <th>Comments</tr>"""),
     [cus_employee(e) for e in c.employees]...,
     HTML("</table></dd></dl>"))

cus_employee(e) =
   H(HTML("<tr><td>"), HE(e.last_name),
         HTML("<td>"), HE(e.first_name),
         HTML("<td>"), HE(e.title),
         HTML("<td><a href='mailto:"), HA(e.email),
                    HTML("'>"), HE(e.email), HTML("</a>"),
         HTML("<td>"), HE(e.main_number),
         HTML("<td>"), HE(e.cell_phone),
         HTML("<td>"),
          [H(HTML("<span>"), HE(c), HTML("</span>")) for c in e.comments]...)

cus_test() = begin
   io = IOBuffer()
   ob = cus_database(database)
   show(io, MIME("text/html"), ob)
   return io
end

pair_result(d) = htl"""
  <html>
    <head><title>$("Customers & Employees")</title></head>
    <body>
    $(map(d) do c; htl⟪
        <dl>
          <dt>Company<dd>$(c.company)
          <dt>Phrase<dd>$(c.phrase)
          <dt>Active Since<dd>$(c.active)
          <dt>Employees<dd>
            <table>
              <tr><th>Last Name<th>First Name<th>Title
                  <th>E-Mail<th>Office Phone<th>Cell Phone
                  <th>Comments</tr>
               $(map(c.employees) do e; htl⟪
                <tr><td>$(e.last_name)<td>$(e.first_name)<td>$(e.title)
                    <td><a href='mailto:$(e.email)'>$(e.email)</a>
                    <td>$(e.main_number)<td>$(e.cell_phone)
                    <td>$(htl⟪<span>$c</span>⟫ for c in e.comments)
               ⟫; end)
            </table>
        </dl>⟫; end)
    </body>
  </html>
"""

pair_test() = begin
   io = IOBuffer()
   ob = pair_result(database)
   show(io, MIME("text/html"), ob)
   return io
end


#BenchmarkTools.DEFAULT_PARAMETERS.seconds = 20
#println("interpolate: ", @benchmark reg_test())
#println("Custom HTML: ", @benchmark cus_test())
#println("Hyperscript: ", @benchmark hs_test())
println("HypertextLiteral: ", @benchmark htl_test())
println("HTL (Attributes): ", @benchmark att_test())
println("Pair Testing: ", @benchmark pair_test())

if false
    open("htl.html", "w") do f
       ob = htl_database(database)
       show(f, MIME("text/html"), ob)
    end
    open("hs.html", "w") do f
       ob = hs_database(database)
       show(f, MIME("text/html"), ob)
    end
    open("reg.html", "w") do f
       ob = reg_database(database)
       show(f, ob)
    end
    open("cus.html", "w") do f
       ob = cus_database(database)
       show(f, MIME("text/html"), ob)
    end
end
