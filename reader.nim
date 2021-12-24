import parseutils, posix, times
import strutils except parseInt

iterator lenPrefixedItems*(f: File, nDigit: int, err=stderr): string =
  ## Parse <fixedWidthItemLenItem\n> with lens ASCII Hexadecimal 0-left-padded &
  ## error messages written to `err` (with "" yield). `err=nil` suppresses.
  var itemLen, item: string
  var iLen, bytes: int

  template e(msg: string) =
    if not err.isNil:
      err.write "lenPrefixedItems(byte", bytes, "): ", msg, '\n'
    yield item
    break

  itemLen.setLen nDigit
  while not f.endOfFile:
    item.setLen 0
    if f.readChars(itemLen) != nDigit   : e "short item length read"
    bytes.inc nDigit
    if parseHex(itemLen, iLen) != nDigit: e "non-integral item length"
    item.setLen iLen+1
    if f.readChars(item) != iLen+1      : e "short item read"
    bytes.inc iLen+1
    if not item.endsWith('\n')          : e "does not end in newline"
    else: item.setLen item.len - 1
    yield item

iterator lenPrefixedPairs*(f: File, nDigit: int, err=stderr): (string, string) =
  var i = 0
  var x: string
  for it in lenPrefixedItems(f, nDigit, err):
    if (i and 1) == 0: x = it
    else: yield (x, it)
    i.inc

template timeIt*(tag: string, body: untyped) =
  let t0=epochTime(); body; echo tag," ",formatFloat(epochTime()-t0,ffDecimal,6)

when isMainModule:
  import os
  var nDigit = 3
  if paramCount() < 1 or parseInt(paramStr(1), nDigit) == paramStr(1).len:
    var kLenHisto, vLenHisto: seq[int]
    for k,v in stdin.lenPrefixedPairs(nDigit):
      if k.len + 1 > kLenHisto.len: kLenHisto.setLen k.len + 1
      kLenHisto[k.len].inc
      if v.len + 1 > vLenHisto.len: vLenHisto.setLen v.len + 1
      vLenHisto[v.len].inc
    for c, n in kLenHisto:
      if n > 0: echo "kl: ", c, " ct: ", n
    for c, n in vLenHisto:
      if n > 0: echo "vl: ", c, " ct: ", n
