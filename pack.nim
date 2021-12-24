## This prog/lib saves space (only a lot for many tiny files) at 0 time cost by
## packing files into back-to-back (2Blen,key,4Blen,val) data & a re-buildable
## hash table index of (ptr,len) pairs pointing to it.  OS FSes *could* support
## this (e.g. cpiofs) but even if so, ditching FS metadata can still save a lot.
##
## This only supports "append" of items with novel keys & data is written first.
## Tables are 0-fill only w/no re-org and when grown a new file is made and put
## in place atomically.  Thus, one-writer/many-reader scenarios need no locks,
## but readers must call `refresh` for an up-to-date views on dynamic data.

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
  result.mode = mode; result.tabN = tabNm; result.datN = datNm
  if mode == fmRead:                    # open read-only
    result.datF = mf.open(datNm)
    result.tabF = mf.open(tabNm)
  elif existsFile datNm:                # open existing read-write
    result.datF = mf.open(datNm, fmReadWrite, allowRemap=true)
    result.tabF = mf.open(tabNm, fmReadWrite, allowRemap=true)
  else:                                 # create empty files
    result.datF = mf.open(datNm, fmReadWrite,-1,0, dat0, true)
    (cast[ptr uint64](result.datF.mem))[] = 8
    result.tabF = mf.open(tabNm, fmReadWrite,-1,0,tab0.slots*TabEnt.sizeof,true)
  result.usedAtOpen = result.used

proc close*(p: var Pack, pad=false) =
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

template iterate(doYield) {.dirty.} =
  var adr  = cast[uint64](p.datF.at 8)
  var left = p.used.int64 - 8
  while left > 0:
    let nK = cast[ptr uint16](adr)[]
    let nV = uint64(cast[ptr ValLen](adr + 2 + nK)[])
    doYield
    let sz = 2 + nK + ValLen.sizeof.uint64 + nV
    adr += sz; left -= sz.int64

iterator keys*(p: Pack): (int, pointer) =
  iterate: yield (nK.int, cast[pointer](adr + 2))

iterator keyVals*(p: Pack): (int, pointer, int, pointer) =
  iterate: yield (nK.int, cast[pointer](adr + 2),
                  nV.int, cast[pointer](adr + 2 + nK + ValLen.sizeof.uint64))

proc refresh*(p: var Pack) =
  if p.mode == fmRead and p.used != p.usedAtOpen:
    p.close; p = packOpen(p.tabN, p.datN)

proc packIndex*(tabNm, datNm: string, tab0=12) =
  if tabNm.existsFile: raise newException(OSError, "\"" & tabNm & "\" exists")
  var p: Pack
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

when isMainModule: #XXX add a `split` to explode into files
  let u = "Usage:\n  pack add PACK FILE_A [..]\n" &
          "    add files FILE_A .. to PACK & index PACK.Nq\n" &
          "  pack cat PACK KEY_A [..]\n    print val for KEY_A ..\n" &
          "  pack list PACK\n    lists keys, one to a line\n" &
          "  pack index PACK\n    recreate PACK.Nq from PACK"
  if paramCount()<1 or paramCount()==1 and paramStr(1)=="help": echo u; quit()
  if paramStr(1) == "add" and paramCount() > 1:
    var pack = packOpen(paramStr(2) & ".Nq", paramStr(2) & ".pa", fmReadWrite)
    for i in 3..paramCount(): pack.add paramStr(i), paramStr(i).readFile
    pack.close
  elif paramStr(1) == "cat" and paramCount() > 1:
    var pack = packOpen(paramStr(2) & ".Nq", paramStr(2) & ".pa")
    for i in 3..paramCount():
      let (n, v) = pack.get(paramStr(i))
      discard stdout.writeBuffer(v, n)
  elif paramStr(1) == "list" and paramCount() > 1:
    var pack = packOpen(paramStr(2) & ".Nq", paramStr(2) & ".pa")
    for key in pack.keys:
      let (nK, k) = key; discard stdout.writeBuffer(k, nK); echo ""
  elif paramStr(1) == "index" and paramCount() > 1:
    packIndex(paramStr(2) & ".Nq", paramStr(2) & ".pa")
  else: echo "Bad usage; Run with no args or with \"help\" for help"; quit(1)
