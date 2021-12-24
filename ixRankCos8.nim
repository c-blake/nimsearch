# Rely on imports/wikipa, do top-N, merge cnt, do seq[Doc], and cosine-rank.
import tables, hashes, strutils, sugar, ./reader, ./terms, ./qutil

type
  Doc = tuple[id: uint32; cnt: uint32]  # documentId, termFreq
  Index = object                        # Inverted Index
    names: seq[string]                  # [doc id] = name (uri, etc.)
    norms: seq[float32]                 # 1.0/sqrt(sum_t(f_dt^2))
    inv: Table[string, seq[Doc]]        # map term -> docId, freqInDoc

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.names[d]), "\n")

let noDocs = newSeq[Doc](0)             # convenience empty set

proc initIndex*(f: File, nDigit=3, nHisto=1): Index =
  for (name, text) in f.lenPrefixedPairs(nDigit):
    var freq = initCountTable[string](nHisto)
    for term in text.terms: freq.inc term
    for term, cnt in freq:
      let doc = (result.names.len.uint32, cnt.uint32)
      result.inv.mgetOrPut(term, noDocs).add doc
    result.names.add name
  result.norms.setLen result.names.len  # pre-compute normalizer for docs
  for docs in result.inv.values:        # could include avg & max a la SMART
    for ic in docs:
      let w = ic.cnt.float
      result.norms[ic.id] += w * w
  for d, norm in result.norms: result.norms[d] = 1.0 / sqrt(norm)

proc find*(ix: Index, query: string, any=false, top=10): seq[uint32] =
  var results: seq[seq[uint32]]
  var relev: Table[uint32, float32]     # query-doc relevance measure
  for term in query.terms:
    let docs = ix.inv.getOrDefault(term, noDocs)
    results.add collect(for d in docs: d.id)
    let idf = if docs.len > 0: idf(ix.names.len, docs.len) else: 0.0
    for ic in docs:
      relev.mgetOrPut(ic.id, 0.0) += ic.cnt.float * idf
  var hq: HeapQueue[(float32, uint32)]
  for d in (if any: union(results) else: intersect(results)):
    hq.pushOrReplace (float32(relev.getOrDefault(d)*ix.norms[d]), d), top
  for e in hq.popAscending: result.add e[1]
  result.reverse                        # Want results in descending order

when isMainModule:
  timeIt("ingest:"): (var ix = stdin.initIndex) # ./data.sh | ./wikipa | ./this
  echo ix.inv.len," unique terms in ",ix.names.len," documents"
  timeIt(" q3:"): echo names(ix, ix.find("London Beer", top=9))
  timeIt(" q4:"): echo names(ix, ix.find("London Beer", any=true, top=9))
