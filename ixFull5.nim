# Here we rely on imports, wikipa, and do top-N-by-relevance results.
import tables, strutils, sugar, ./reader, ./terms, ./qutil

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

proc initIndex*(f: File, nDigit=3): Index =
  for (name, text) in f.lenPrefixedPairs(nDigit):
    result.docs.setLen result.docs.len + 1
    result.docs[^1].name = name
    result.docs[^1].freq = initCountTable[string](1) # Abstracts can be tiny
    for term in text.terms: result.docs[^1].freq.inc term
    for term, cnt in result.docs[^1].freq:
      result.inv.mgetOrPut(term, noDocs).incl uint32(result.docs.len - 1)

proc find*(ix: Index, query: string, any=false, top=0): seq[uint32] =
  var results: seq[HashSet[uint32]]
  var qterms: seq[string]
  var idf: seq[float]
  for term in query.terms:
    qterms.add term
    let docs = ix.inv.getOrDefault(term, noDocs)
    idf.add if docs.len > 0: idf(ix.docs.len, docs.len) else: 0.0
    results.add docs
  let res = if any: union(results) else: intersect(results)
  if top == 0: return collect(for d in res: d)  # no ranking => Done!
  var hq: HeapQueue[(float32, uint32)]
  for d in res:
    var s = 0.0'f32                     # Relevance score
    for i, t in qterms: s += ix.docs[d].freq.getOrDefault(t).float*idf[i]
    hq.pushOrReplace (s, d), top
  for e in hq.popAscending: result.add e[1]
  result.reverse                        # Want results in descending order

when isMainModule:
  timeIt("ingest:"): (var ix = stdin.initIndex) # ./data.sh | ./wikipa | ./this
  echo ix.inv.len," unique terms in ",ix.docs.len," documents"
  timeIt(" q1:"): echo names(ix, ix.find("London Beer"))
  timeIt(" q2:"): echo ix.find("London Beer", any=true).len
  timeIt(" q3:"): echo names(ix, ix.find("London Beer", top=9))
  timeIt(" q4:"): echo names(ix, ix.find("London Beer", any=true, top=9))
