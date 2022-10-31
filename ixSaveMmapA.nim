# Rely on imports/wikipa, do top-N, merge cnt, do seq[Doc], cosine-rank & Mmap.
when not declared(File): import std/syncio
import tables, hashes, strutils, sugar, os, ./reader, ./terms, ./qutil
from memfiles as mf import nil
type
  Doc = tuple[id: uint32; cnt: uint32]  # documentId, termFreq
  Index = object                        # Inverted Index
    nmD, nmP, nrm: mf.MemFile           # data & offLen files
    path: string                        # DocSet = load(path & term)

proc nD(ix: Index): auto = cast[ptr UncheckedArray[byte]](ix.nmD.mem)
proc nP(ix: Index): auto = cast[ptr UncheckedArray[uint32]](ix.nmP.mem)
proc name(ix: Index, i: uint32): string = $cast[cstring](ix.nD[ix.nP[i]].addr)
proc norms(ix: Index): auto = cast[ptr UncheckedArray[float32]](ix.nrm.mem)
proc nDoc*(ix: Index): uint32 = uint32(ix.nmP.size div 4)

proc names*(ix: auto, docs: auto, prefix=""): string =
  join(collect(for d in docs: prefix & ix.name(d)), "\n")

let noDocs = newSeq[Doc](0)             # convenience empty set

proc buildSave*(f: File, path="/dev/shm/ix", nDigit=3, nHisto=1) =
  var nmData = open(path/"NMDATA0", fmWrite)  # lowercase terms cannot collide
  var nmPtrs = open(path/"NMDATA.NI", fmWrite)
  var inv: Table[string, seq[Doc]]            # map term -> docId, freqInDoc
  var nDoc, off: uint32
  for (name, text) in f.lenPrefixedPairs(nDigit):
    discard nmPtrs.writeBuffer(off.addr, off.sizeof)
    nmData.write name, '\0'; off += uint32(name.len + 1)
    var freq = initCountTable[string](nHisto)
    for term in text.terms: freq.inc term
    for term, cnt in freq: inv.mgetOrPut(term, noDocs).add (nDoc, cnt.uint32)
    nDoc.inc
  nmData.close; nmPtrs.close
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
  result.nmD  = mf.open(path/"NMDATA0")
  result.nmP  = mf.open(path/"NMDATA.NI")
  result.nrm  = mf.open(path/"NORMS.Nf")
  result.path = path

proc getOrDefault(ix: Index, term: string, dflt: seq[Doc]): seq[Doc] =
  try:
    var dset = mf.open(ix.path/term)
    result.setLen dset.size div 4
    for i in 0 ..< result.len:
      let num = cast[ptr uint32](cast[uint](dset.mem) + cast[uint](4*i))[]
      result[i] = (num shr 7, (num and 0x7F) * (num and 0x7F))
    mf.close dset
  except: discard # return is empty seq by default

proc find*(ix: Index, query: string, any=false, top=10): seq[uint32] =
  var results: seq[seq[uint32]]
  var relev: Table[uint32, float32]     # query-doc relevance measure
  for term in query.terms:
    let docs = ix.getOrDefault(term, noDocs)
    results.add collect(for d in docs: d.id)
    let idf = if docs.len > 0: idf(ix.nDoc, docs.len) else: 0.0
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
