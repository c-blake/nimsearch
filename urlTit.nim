import sets, strutils, uri, ./wikipa # Test how to urlify a title

proc urlify(s: string): string =
  s.replace(' ', '_').encodeUrl.replace("%28", "(").replace("%29", ")").
   replace("%2C", ",").replace("%3A",":").replace("%2F","/").replace("%21","!").
   replace("%2A", "*").replace("%40","@").replace("%24","$").replace("%3B",";")

var title, url: string
let fields = ["title", "url"].toHashSet
for (e, t) in xml(stdin, "stdin", fields):
  case e
  of "title":
    title = if t.startsWith(tPrefix): t[tPrefix.len..^1] else: t
  of "url":
    url   = if t.startsWith(uPrefix): t[uPrefix.len..^1] else: t
    if url != title and url != title.urlify:
      echo "t: ", title.urlify
      echo "u: ", url
