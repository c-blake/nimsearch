## Canonicalize enwiki-multistream.xml
import sets, xml, uri, strutils

proc urlify*(s: string): string =
  s.replace(' ', '_').encodeUrl.replace("%28", "(").replace("%29", ")").
   replace("%2C", ",").replace("%3A",":").replace("%2F","/").replace("%21","!").
   replace("%2A", "*").replace("%40","@").replace("%24","$").replace("%3B",";")

proc main() =           #NOTE: item lens do not include mandatory newline.
  const nDigit = 6      # biggest article is 3.7; 16 MiB probably ok.
  let fields = ["title", "text"].toHashSet
  var url: string
  for (e, t) in xml(stdin, "stdin", fields):
    case e              # Wikipedia <text> always follows <title>
    of "title": url = t.urlify
    of "text":
      if t.len > 9:
        let s = t[0..8].toLowerASCII
        if s != "#redirect":
          stdout.write url.len.toHex(nDigit), url, '\n'
          stdout.write t.len.toHex(nDigit), t, '\n'
      url.setLen 0

when isMainModule: main()  # ./data.sh | ./this | ./tindex
