# Like ixAllInOneEasy1.nim but rely on imports and wikipa preprocessing.
when not declared(File): import std/syncio
import tables, strutils, sugar, ./reader, ./terms, ./qutil

type Index = object                     # Inverted Index
  names: seq[string]                    # [doc id] = name (uri, etc.)
  inv: Table[string, HashSet[uint32]]   # map term -> docs

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.names[d]), "\n")

let noDocs = initHashSet[uint32](0)     # convenience empty set

proc initIndex*(f: File, nDigit=3): Index = # CORE LOGIC: this & `find`
  for (name, text) in f.lenPrefixedPairs(nDigit):
    var freq = initCountTable[string](1) # Abstracts can be tiny
    for term in text.terms: freq.inc term
    for term, cnt in freq:
      result.inv.mgetOrPut(term, noDocs).incl uint32(result.names.len)
    result.names.add name

proc find*(ix: Index, query: string, any=false): HashSet[uint32] =
  var results: seq[HashSet[uint32]]
  for term in query.terms:
    results.add ix.inv.getOrDefault(term, noDocs)
  result = if any: union(results) else: intersect(results)

when isMainModule:
  timeIt("ingest:"): (var ix = stdin.initIndex) # ./data.sh | ./wikipa | ./this
  echo ix.inv.len," unique terms in ",ix.names.len," documents"
  timeIt(" q1:"): echo names(ix, ix.find("London Beer"))
  timeIt(" q2:"): echo ix.find("London Beer", any=true).len
