# Rely on imports, wikipa, do top-N, merge cnt into `Doc`, compct via seq[Doc]
import tables, hashes, strutils, sugar, ./reader, ./terms, ./qutil

type
  Doc = tuple[id: uint32; cnt: uint32]  # documentId, termFreq
  Index = object                        # Inverted Index
    names: seq[string]                  # [doc id] = name (uri, etc.)
    inv: Table[string, seq[Doc]]        # map term -> docId, freqInDoc

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.names[d]), "\n")

let noDocs = newSeq[Doc](0)             # convenience empty set

proc initIndex*(f: File, nDigit=3, nHisto=1): Index =
  for (name, text) in f.lenPrefixedPairs(nDigit):
    var freq = initCountTable[string](nHisto)
    for term in text.terms: freq.inc term
    for term, cnt in freq:
      result.inv.mgetOrPut(term,noDocs).add (result.names.len.uint32,cnt.uint32)
    result.names.add name

proc find*(ix: Index, query: string, any=false, top=0): seq[uint32] =
  var results: seq[seq[uint32]]
  var tFreq: seq[Table[uint32, uint32]]
  var idf: seq[float]
  for term in query.terms:
    let docs = ix.inv.getOrDefault(term, noDocs)
    idf.add if docs.len > 0: idf(ix.names.len, docs.len) else: 0.0
    results.add collect(for d in docs: d.id)
    tFreq.add   collect(for d in docs: {d.id: d.cnt})
  let res = if any: union(results) else: intersect(results)
  if top == 0: return collect(for d in res: d)  # no ranking => Done!
  var hq: HeapQueue[(float32, uint32)]
  for d in res:
    var s = 0.0'f32                     # Relevance score
    for i in 0..<tFreq.len: s += tFreq[i].getOrDefault(d).float*idf[i]
    hq.pushOrReplace (s, d), top
  for e in hq.popAscending: result.add e[1]
  result.reverse                        # Want results in descending order

when isMainModule:
  timeIt("ingest:"): (var ix = stdin.initIndex) # ./data.sh | ./wikipa | ./this
  echo ix.inv.len," unique terms in ",ix.names.len," documents"
  timeIt(" q1:"): echo names(ix, ix.find("London Beer"))
  timeIt(" q2:"): echo ix.find("London Beer", any=true).len
  timeIt(" q3:"): echo names(ix, ix.find("London Beer", top=9))
  timeIt(" q4:"): echo names(ix, ix.find("London Beer", any=true, top=9))
