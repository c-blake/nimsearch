# Rely on imports/wikipa, do top-N, merge cnt, do seq[Doc], cosine-rank & SAVE.
when not declared(File): import std/syncio
import tables, hashes, strutils, sugar, os, ./reader, ./terms, ./qutil

type
  Doc = tuple[id: uint32; cnt: uint32]  # documentId, termFreq
  Index = object                        # Inverted Index
    names: seq[string]                  # [doc id] = name (uri, etc.)
    norms: seq[float32]                 # 1.0/sqrt(sum_t(f_dt^2))
    path: string                        # DocSet = load(path & term)

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.names[d]), "\n")

let noDocs = newSeq[Doc](0)             # convenience empty set

proc buildSave*(f: File, path="/dev/shm/ix", nDigit=3, nHisto=1) =
  var names = open(path/"NAMES", fmWrite) # lowercase terms cannot collide
  var inv: Table[string, seq[Doc]]        # map term -> docId, freqInDoc
  var nDoc: uint32
  for (name, text) in f.lenPrefixedPairs(nDigit):
    names.write name, '\n'
    var freq = initCountTable[string](nHisto)
    for term in text.terms: freq.inc term
    for term, cnt in freq: inv.mgetOrPut(term, noDocs).add (nDoc, cnt.uint32)
    nDoc.inc
  names.close
  var norms = newSeq[float32](nDoc)
  for term, docs in inv:                # save inv index to disk
    var f = open(path/term, fmWrite)    # shrink by back-to-back docs w/term ptr
    for d in docs:
      var ic = (d.id shl 7) or
                (sqrt(min((1 shl 14)-1, d.cnt.int).float).uint32 and 0x7F)
      discard f.writeBuffer(ic.addr, ic.sizeof)
      norms[d.id] += d.cnt.float * d.cnt.float
    f.close
  for d, norm in norms: norms[d] = 1.0 / sqrt(norm)
  var normsF = open(path/"NORMS.Nf", fmWrite)
  discard normsF.writeBuffer(norms[0].addr, 4*norms.len)
  normsF.close

proc initIndex*(path="/dev/shm/ix"): Index =
  result.path  = path   # ~1 sec; Could easily mmap & go via some NAME_START.ix
  result.names = collect(for name in lines(path/"NAMES"): name)
  result.norms.setLen result.names.len
  var normsF = open(path/"NORMS.Nf")
  discard normsF.readBuffer(result.norms[0].addr, 4*result.norms.len)
  normsF.close

proc getOrDefault(ix: Index, term: string, dflt: seq[Doc]): seq[Doc] =
  try:
    let nm = ix.path/term
    let sz = nm.getFileSize
    var f = open(nm, fmRead)
    var data = newSeq[uint32](sz div 4)
    discard f.readBuffer(data[0].addr, sz)
    f.close
    for num in data: result.add (num shr 7, (num and 0x7F) * (num and 0x7F))
  except: discard # return is empty seq by default

proc find*(ix: Index, query: string, any=false, top=10): seq[uint32] =
  var results: seq[seq[uint32]]
  var relev: Table[uint32, float32]     # query-doc relevance measure
  for term in query.terms:
    let docs = ix.getOrDefault(term, noDocs)
    results.add collect(for d in docs: d.id)
    let idf = if docs.len > 0: idf(ix.names.len, docs.len) else: 0.0
    for ic in docs: relev.mgetOrPut(ic.id, 0.0) += ic.cnt.float * idf
  var hq: HeapQueue[(float32, uint32)]
  for d in (if any: union(results) else: intersect(results)):
    hq.pushOrReplace (float32(relev.getOrDefault(d)*ix.norms[d]), d), top
  for e in hq.popAscending: result.add e[1]
  result.reverse                        # Want results in descending order

when isMainModule: # nim c -d:danger --gc:arc -d:useMalloc --passC:-flto this
  if paramCount() > 2: stdin.buildSave(paramStr(1),parseInt(paramStr(3)));quit()
  if paramCount() > 1: stdin.buildSave(paramStr(1)); quit()
  var ix = initIndex(if paramCount() > 0: paramStr(1) else: "/dev/shm/ix")
  echo "\"top <N>\" changes result limit; \"mode o*\" OR else AND queries."
  var any = false; var top = 10 # ./data.sh|./wikipa|./this /tmp/ix build;./this
  while not stdin.endOfFile:
    let line = stdin.readLine
    let cmd = line.toLowerASCII.split(' ', 1)
    case cmd[0]
    of "top" : top = parseInt(cmd[1]); echo "show top ",top," results"
    of "mode": any = cmd[1].toLowerASCII.startsWith("o"); echo "OR mode: ",any
    else: timeIt("query"): echo names(ix, ix.find(line, any, top))
