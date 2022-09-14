## This lib/prog saves space (only a lot for many tiny files) at 0 time cost by
## packing files into back-to-back (2Blen,key,4Blen,val) data & a re-makable
## hash table index of (ptr,len) pairs pointing to it.  OS FSes *could* support
## this (e.g. cpiofs) but even if so, ditching FS metadata can still save a lot.
##
## This only supports "append" of items with novel keys & data is written first.
## Tables are 0-fill only w/no re-org.  When grown a new file is made and put in
## place atomically.  Thus, one-writer/many-reader scenarios need no locks, but
## readers must call `refresh` for an up-to-date view of dynamic data.

import hashes, os, memfiles as mf, math
proc memcmp(a, b: pointer; n: csize_t): cint {.header: "<string.h>".}

const nlBits = 16                       # 64 KiB a pretty big "key" and..
const nlMask = (1 shl nlBits) - 1       #..leaves 2^48 = 1/4 PiB addr space.
type
  TabEnt = distinct uint64
  ValLen = distinct uint32              # Could maybe be a generic parameter
  Pack* = object
    mode: FileMode
    tabN, datN: string
    tabF, datF: mf.MemFile
    usedAtOpen: uint64
  Ptrs = ptr UncheckedArray[TabEnt]

proc at(f: mf.MemFile, o: int): auto = cast[pointer](cast[uint](f.mem) + o.uint)
proc cnt(p: Pack): auto = cast[ptr TabEnt](p.tabF.mem)
proc tab(p: Pack): auto = cast[Ptrs](p.tabF.at(TabEnt.sizeof))
proc off(x: TabEnt): auto = uint64(x) shr nlBits
proc len(x: TabEnt): auto = uint64(x) and nlMask
proc key(p: Pack, te: TabEnt): auto = (te.len.int, p.datF.at(te.off.int + 2))
proc val(p: Pack, te: TabEnt): (int, pointer) =
  let v = cast[int](p.datF.at(te.off.int + 2 + te.len.int))
  (cast[ptr ValLen](v)[].int, cast[pointer](v + ValLen.sizeof))
proc used* (p: Pack): auto = cast[ptr uint64](p.datF.mem)[] #XXX atomic acquire
proc slots*(p: Pack): auto = p.tabF.size div TabEnt.sizeof - 1
proc tooFull(c, s: int): bool = (c * 16 > s * 13) or (s < c + 16)
proc slots(c: int): int = 1 + nextPowerOfTwo(c * 16 div 13 + 16)

proc packOpen*(tabNm, datNm: string, mode=fmRead, tab0=12, dat0=128): Pack =
  ## Open|make a pack file & its index.  For pre-sizing, `tab0` is the initial
  ## number of keys while `dat0` is the initial data size in bytes.
  result.mode = mode; result.tabN = tabNm; result.datN = datNm
  if mode == fmRead:                    # open read-only
    result.datF = mf.open(datNm)
    result.tabF = mf.open(tabNm)
  elif fileExists datNm:                # open existing read-write
    result.datF = mf.open(datNm, fmReadWrite, allowRemap=true)
    result.tabF = mf.open(tabNm, fmReadWrite, allowRemap=true)
  else:                                 # create empty files
    result.datF = mf.open(datNm, fmReadWrite,-1,0, dat0, true)
    (cast[ptr uint64](result.datF.mem))[] = 8
    result.tabF = mf.open(tabNm, fmReadWrite,-1,0,tab0.slots*TabEnt.sizeof,true)
  result.usedAtOpen = result.used

proc close*(p: var Pack, pad=false) =
  ## Release OS resources for an open pack file.
  p.tabF.close
  if p.mode == fmReadWrite and not pad: p.datF.resize p.used.int
  p.datF.close

proc find(p: Pack, q: string|TabEnt, h: Hash): int =
  let mask = p.slots - 1
  var i = h and mask
  while (let te = p.tab[i]; uint64(te) != 0):
    when q is string: # else: table grow find always a novel key
      let (n, k) = p.key(te)
      if n == q.len and memcmp(k, q[0].unsafeAddr, n.csize_t) == 0:
        return i
    i = (i + 1) and mask
  -i - 1                                # missing insert @ -(result)-1

proc get*(p: Pack; key: string): (int, pointer) =
  ## Find the value buffer for a given `key`.
  let i = p.find(key, hash(key))
  if i < 0: (0, nil) else: p.val(p.tab[i])

proc growTab(p: var Pack) =
  var mold = p.tabF
  let tOld = cast[Ptrs](cast[uint](mold.mem) + TabEnt.sizeof.uint)
  let nOld = p.slots
  let tmp  = p.tabN & ".tmp"
  p.tabF = mf.open(tmp, fmReadWrite, -1, 0, (2*p.slots+1)*TabEnt.sizeof, true)
  for i in 0 ..< nOld:
    if (let te = tOld[i]; uint64(te) != 0):
      let (n, k) = p.key(te)
      let h = hash(toOpenArray[byte](cast[ptr UncheckedArray[byte]](k), 0, n-1))
      p.tab[-p.find(te, h) - 1] = te
  p.cnt[] = (cast[ptr TabEnt](mold.at(0)))[]
  mold.close
  moveFile tmp, p.tabN                  # atomic replace

proc add*(p: var Pack; key, val: string) =
  ## Add (`key`, `val`) pair to an open, writable pack.
  if key.len > uint16.high.int: raise newException(ValueError, "key too long")
  if val.len > ValLen.high.int: raise newException(ValueError, "val too long")
  let h = key.hash
  var i = p.find(key, h)
  if i >= 0: raise newException(ValueError, "key \"" & key & "\" present")
  let u = p.used.int; var keyLen = key.len.uint16
  var valLen = val.len.ValLen; let vls = valLen.sizeof
  if p.datF.size < (let room = u + key.len + 2 + vls + val.len; room):
    let nsz = ((room shl 1) + 4096) and not 4095
    p.datF.resize nsz                   # boost alloc to 2x size needed now
  copyMem p.datF.at(u                    ), keyLen.addr      , 2
  copyMem p.datF.at(u + 2                ), key[0].unsafeAddr, key.len
  copyMem p.datF.at(u + 2 + key.len      ), valLen.addr      , vls
  copyMem p.datF.at(u + 2 + key.len + vls), val[0].unsafeAddr, val.len
  if tooFull(int(p.cnt[]) + 1, p.slots):
    p.growTab; i = p.find(key, h)
  i = -i - 1
  p.tab[i] = TabEnt((p.used shl nlBits) or uint64(key.len))
  p.cnt[].inc #XXX atomic store release to ensure p.refresh works right on ARM
  (cast[ptr uint64](p.datF.mem))[] += uint64(key.len + 2 + vls + val.len)

template iterate(doYield) {.dirty.} =   # This just iterates over the back-to-
  var adr  = cast[uint64](p.datF.at 8)  #..back format of the data file.
  var left = p.used.int64 - 8
  while left > 0:
    let nK = cast[ptr uint16](adr)[]
    let nV = uint64(cast[ptr ValLen](adr + 2 + nK)[])
    doYield
    let sz = 2 + nK + ValLen.sizeof.uint64 + nV
    adr += sz; left -= sz.int64

iterator keys*(p: Pack): (int, pointer) =
  ## Iterate over just the keys in an open pack file.
  iterate: yield (nK.int, cast[pointer](adr + 2))

iterator keyVals*(p: Pack): (int, pointer, int, pointer) =
  ## Iterate over just the vals in an open pack file.
  iterate: yield (nK.int, cast[pointer](adr + 2),
                  nV.int, cast[pointer](adr + 2 + nK + ValLen.sizeof.uint64))

proc refresh*(p: var Pack) =
  ## Re-open a read-only pack only if necessary; Fast when unneeded.
  if p.mode == fmRead and p.used != p.usedAtOpen:
    p.close; p = packOpen(p.tabN, p.datN)

proc packIndex*(tabNm, datNm: string, tab0=12) =
  ## Re-make a hash index from the back-to-back file of records.
  if tabNm.fileExists: raise newException(OSError, "\"" & tabNm & "\" exists")
  var p: Pack           # Only a partial `packOpen`; table need not exist
  p.datF = mf.open(datNm)
  p.usedAtOpen = p.used; p.mode = fmRead; p.tabN = tabNm; p.datN = datNm
  p.tabF = mf.open(tabNm, fmReadWrite, -1, 0, tab0.slots*TabEnt.sizeof, true)
  var key: string
  for k in p.keys:
    key.setLen k[0]; copyMem key[0].addr, k[1], k[0]
    let h = key.hash
    var i = p.find(key, h)
    if i >= 0: raise newException(ValueError, "key \"" & key & "\" present")
    if tooFull(int(p.cnt[]) + 1, p.slots):
      p.growTab; i = p.find(key, h)
    i = -i - 1
    p.tab[i] = TabEnt(((cast[uint64](k[1]) - cast[uint64](p.datF.mem) - 2) shl
                       nlBits) or uint64(key.len))
    p.cnt[].inc
  p.close

proc packSplit*(datNm: string) =  # Could take an outName(key) name maker
  ## Split a pack data file into its components
  var p: Pack           # Only a partial `packOpen`; table need not exist
  p.datF = mf.open(datNm)
  p.usedAtOpen = p.used; p.mode = fmRead; p.datN = datNm
  var key: string
  for kv in p.keyVals:
    key.setLen kv[0]; copyMem key[0].addr, kv[1], kv[0]
    key.writeFile toOpenArray[byte](cast[ptr UncheckedArray[byte]](kv[3]),
                                    0, kv[2] - 1)

when isMainModule:
  import std/strutils; template match(s): untyped = paramStr(1).startsWith(s)
  let u = """Usage:
  pack a)dd   PACK FILE_A [..] add files FILE_A .. to PACK & index PACK.NL
  pack c)at   PACK KEY_A [..]  print val for KEY_A ..
  pack l)ist  PACK             lists keys, one to a line
  pack i)ndex PACK             recreate PACK.NL from PACK
  pack s)plit PACK             split PACK.NL into files"""
  if paramCount() < 1 or paramCount() == 1 and match("h"): echo u; quit()
  if match("a") and paramCount() > 1:   # Add
    var pack = packOpen(paramStr(2) & ".NL", paramStr(2) & ".pa", fmReadWrite)
    for i in 3..paramCount(): pack.add paramStr(i), paramStr(i).readFile
    pack.close
  elif match("c") and paramCount() > 1: # Cat|Get
    var pack = packOpen(paramStr(2) & ".NL", paramStr(2) & ".pa")
    for i in 3..paramCount():
      let (n, v) = pack.get(paramStr(i))
      discard stdout.writeBuffer(v, n)
  elif match("l") and paramCount() > 1: # List
    var pack = packOpen(paramStr(2) & ".NL", paramStr(2) & ".pa")
    for key in pack.keys:
      let (nK, k) = key; discard stdout.writeBuffer(k, nK); echo ""
  elif match("i") and paramCount() > 1: # Index
    packIndex(paramStr(2) & ".NL", paramStr(2) & ".pa")
  elif match("s") and paramCount() > 1: # Split
    packSplit(paramStr(2) & ".pa")
  else: echo "Bad usage; Run with no args or with \"help\" for help"; quit(1)
