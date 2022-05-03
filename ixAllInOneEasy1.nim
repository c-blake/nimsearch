# The essence of the problem/solution all in a single file.
import sets, tables, strutils, streams, parsexml, sugar, times

iterator words(text: string): string =  # Tokenizer; could go UTF8, limit..
  var word = ""                         #..length of pure numeric, etc.
  for c in text:
    if   c in {'A'..'Z'}: word.add char(ord(c) + 32)
    elif c in {'a'..'z'}: word.add c    # Add '0'..'9' maybe with len limit?
    elif word.len > 0: yield word; word.setLen 0
  if word.len > 0: yield word

iterator terms(text: string): string =  # yield indexed words in `text`
  for word in text.words: yield word

iterator xml(f: File, name: string, elements: HashSet[string], dataKinds =
             {xmlCharData,xmlWhitespace,xmlCData,xmlEntity}): (string, string) =
  var x: XmlParser                      # yield (elName, innerText) for elements
  open(x, f.newFileStream, name)
  x.next                                # get to first XML element
  var t = ""
  while x.kind != xmlEof:
    if x.kind == xmlElementStart and (let e = x.elementName; e in elements):
      x.next; t.setLen 0                # skip ElementStart; trunc yielded
      while not (x.kind == xmlElementEnd and x.elementName == e):
        if x.kind in dataKinds: t.add x.charData
        x.next
      yield (e, t)
    else: x.next
  x.close

proc intersect(results: var seq[HashSet[uint32]]): HashSet[uint32] =
  for i in 1..<results.len: results[0] = results[0].intersection(results[i])
  results[0]

proc union(results: var seq[HashSet[uint32]]): HashSet[uint32] =
  for i in 1..<results.len: results[0] = results[0].union(results[i])
  results[0]

type Index = object                     # Inverted Index
  names: seq[string]                    # [doc id] = name (uri, etc.)
  inv: Table[string, HashSet[uint32]]   # map term -> docs

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.names[d]), "\n")

let noDocs = initHashSet[uint32](0)     # convenience empty set

proc initIndex*(f: File, name=""): Index = # CORE LOGIC: this & `find`
  var name, title: string; const pfx = "https://en.wikipedia.org/wiki/"
  for (e, t) in xml(f, name, ["title", "url", "abstract"].toHashSet):
    case e
    of "title": title = if t.startsWith("Wikipedia: "): t[11..^1] else: t
    of "url": name = if t.startsWith(pfx): t[pfx.len..^1] else: t
    of "abstract":
      var freq = initCountTable[string](1) # Abstracts can be tiny
      for term in terms(title & " " & t): freq.inc term
      for term, cnt in freq:               # should skip if no terms
        result.inv.mgetOrPut(term, noDocs).incl uint32(result.names.len)
      result.names.add name; title.setLen 0; name.setLen 0

proc find*(ix: Index, query: string, any=false): HashSet[uint32] =
  var results: seq[HashSet[uint32]]
  for term in query.terms: results.add ix.inv.getOrDefault(term, noDocs)
  result = if any: union(results) else: intersect(results)

template timeIt(tag: string, body: untyped) =
  let t0=epochTime(); body; echo tag," ",formatFloat(epochTime()-t0,ffDecimal,6)
timeIt("ingest:"): (var ix = stdin.initIndex) # ./data.sh | ./this
echo ix.inv.len," unique terms in ",ix.names.len," documents"
timeIt(" q1:"): echo names(ix, ix.find("London Beer"))
timeIt(" q2:"): echo ix.find("London Beer", any=true).len
