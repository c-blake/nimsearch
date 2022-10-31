## Canonicalize dumps.wikimedia.org/enwiki/latest/enwiki-latest-abstract.xml
when not declared(stdout): import std/syncio
import sets, strutils, xml
when defined(skipEmpty):
  import terms

const tPrefix* = "Wikipedia: "
const uPrefix* = "https://en.wikipedia.org/wiki/"

proc main*() =      #NOTE: item lens do not include mandatory newline.
  const nDigit = 3  # 4095 bytes ok for uri & abstract (max == 1026)
  var title, url: string
  when defined(skipEmpty):
    var skipped = 0
  let fields = ["title", "url", "abstract"].toHashSet
  for (e, t) in xml(stdin, "stdin", fields):
    case e
    of "title": title = if t.startsWith(tPrefix): t[tPrefix.len..^1] else: t
    of "url"  : url   = if t.startsWith(uPrefix): t[uPrefix.len..^1] else: t
    of "abstract":  # Wikipedia <abstract> always ends a 3-cycle.
      when defined(skipEmpty):
        var count = 0
        for term in t.terms: count.inc
        if count == 0: title.setLen 0; url.setLen 0; skipped.inc; continue
      stdout.write url.len.toHex(nDigit)
      stdout.write url, '\n'
      stdout.write (title.len + 1 + t.len).toHex(nDigit)
      stdout.write title, '\n', t, '\n'
      title.setLen 0; url.setLen 0
  when defined(skipEmpty):
    stderr.write "skipped ", skipped, " empty abstracts."

when isMainModule:  # ./data.sh | ./this | ./tindex
  main()
