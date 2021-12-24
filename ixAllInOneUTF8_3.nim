# Here we add UTF8 tokenizing and properly stem stops.
import sets,tables,math,strutils,algorithm,streams,parsexml,sugar,times,unicode

{.passl: "/usr/lib64/libstemmer.so".}   # YOU MAY NEED TO ADJUST THIS!
type sb_stemmer {.bycopy.} = object
proc sb_stemmer_new(algo: cstring; charenc: cstring): ptr sb_stemmer
  {.importc: "sb_stemmer_new".}
proc sb_stemmer_stem(stm: ptr sb_stemmer; word: cstring; size: cint): cstring
  {.importc: "sb_stemmer_stem".}
proc sb_stemmer_length(stm:ptr sb_stemmer):cint {.importc: "sb_stemmer_length".}

let stm = sb_stemmer_new("english", "UTF_8")
proc stem(word: string): string =       # wrap snowball stemmer for English
  let cs = stm.sb_stemmer_stem(word, word.len.cint)
  let cn = stm.sb_stemmer_length
  result.setLen int(cn)
  copyMem result[0].addr, cs, int(cn)

iterator words(text: string): string =  # basic utf8 tokenizer
  var word = ""
  var rstr = "1234567"
  var someASCII = false
  template maybeYield {.dirty.} =
    if someASCII: yield word
    word.setLen 0
    someASCII = false
  for rune in runes(text):
    let rune = rune.toLower
    fastToUTF8Copy(rune, rstr, 0, false)
    if rune.isLower:                    # Add '0'..'9' maybe with len limit?
      word.add rstr
      if rstr.len==1: someASCII = true  # Reject words with no ASCII at all
    elif word.len > 0: maybeYield
  if word.len > 0: maybeYield

const STOP = ["the", "be", "to", "of", "and", "a", "in", "that", "have", "for",
  "i", "it", "not", "on", "with", "he", "as", "you", "do", "at", "this", "but",
  "his", "by", "from", "is", "was", "or", "s", "an", "may", "new", "are", "who",
  "which", "name", "also", "has", "its", "born", "birth", "place", "places",
  "known", "refer", "refers" ].toHashSet # Last few Wikipedia-specific

let STOP_STEMMED = collect(for stop in STOP: { stem(stop) })

iterator terms(text: string): string =  # yield stemmed non-stop words in `text`
  for word in unicode.toLower(text).words:
    let word = stem(word)               # NOTE: Must stem STOPs if ix/qry stems.
    if word notin STOP_STEMMED: yield word

iterator xml(f: File, name: string, elements: HashSet[string], dataKinds =
             {xmlCharData,xmlWhitespace,xmlCData,xmlEntity}): (string, string) =
  var x: XmlParser                      # yield (elName, innerText) for elements
  open(x, f.newFileStream, name)
  x.next                                # get to first XML element
  var t = ""
  while x.kind != xmlEOF:
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

type                            # Main code: Here to end of `find`
  Doc = object                          # Abstraction of a "document"
    name: string                        # document metadata
    freq: CountTable[string]            # histo of terms; Should put into uint32
  Index = object                        # Inverted Index
    docs: seq[Doc]                      # uint32-keyed dyn.array
    inv: Table[string, HashSet[uint32]] # map term -> docs; ~50-50 inv,docs spc

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.docs[d].name), "\n")

let noDocs = initHashSet[uint32](0)     # convenience empty set

proc initIndex*(f: File, name=""): Index = # CORE LOGIC: this & `find`
  var doc: Doc; var title: string; const pfx = "https://en.wikipedia.org/wiki/"
  for (e, t) in xml(f, name, ["title", "url", "abstract"].toHashSet):
    case e
    of "title": title = if t.startsWith("Wikipedia: "): t[11..^1] else: t
    of "url": doc.name = if t.startsWith(pfx): t[pfx.len..^1] else: t
    of "abstract":
      doc.freq = initCountTable[string](1) # Abstracts can be tiny
      for term in terms(title & " " & t): doc.freq.inc term
      for term, cnt in doc.freq:           # should skip if no terms
        result.inv.mgetOrPut(term, noDocs).incl uint32(result.docs.len)
      result.docs.add doc; title.setLen 0

proc find*(ix: Index, query: string, any=false, rank=false): seq[uint32] =
  var qterms: seq[string]
  var idf: seq[float]
  var results: seq[HashSet[uint32]]
  for term in query.terms:
    qterms.add term
    let docs = ix.inv.getOrDefault(term, noDocs)
    idf.add if docs.len > 0: ln(ix.docs.len.float / docs.len.float) else: 0.0
    results.add docs
  let res = if any: union(results) else: intersect(results)
  if not rank: return collect(for d in res: d)  # no ranking => Done!
  var r: seq[(float, uint32)]
  for d in collect(for d in(if any: union(results) else:intersect(results)): d):
    var s = 0.0                         # Relevance score
    for i, term in qterms:              # Here: actual term count*log(N/docFreq)
      s += float(ix.docs[d].freq.getOrDefault(term)) * idf[i]
    r.add (s, d)
  r.sort(order=Descending)
  for (_, d) in r: result.add d

template timeIt(tag: string, body: untyped) =
  let t0=epochTime(); body; echo tag," ",formatFloat(epochTime()-t0,ffDecimal,6)
timeIt("ingest:"): (var ix = initIndex(stdin, "stdin")) # ./data.sh | ./this
echo ix.inv.len," unique terms in ",ix.docs.len," documents"
timeIt(" q1:"): echo names(ix, ix.find("London Beer"))
timeIt(" q2:"): echo ix.find("London Beer", any=true).len
timeIt(" q3:"): echo names(ix, ix.find("London Beer", rank=true))
timeIt(" q4:"): echo names(ix, ix.find("London Beer", any=true, true)[0..9])
