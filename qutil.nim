import std/[sets, math, heapqueue, algorithm]
export sets, sqrt, heapqueue, algorithm

proc intersection*[T](a, b: seq[T]): seq[T] =
  var i, j: int
  while i < a.len and j < b.len:
    if   a[i] < b[j]: i.inc
    elif b[j] < a[i]: j.inc
    else: result.add b[j]; i.inc; j.inc

proc union*[T](a, b: seq[T]): seq[T] =
  var i, j: int
  while i < a.len and j < b.len:
    if   a[i] < b[j]: result.add a[i]; i.inc
    elif b[j] < a[i]: result.add b[j]; j.inc
    else: result.add b[j]; j.inc; i.inc

proc intersect*[T](results: var seq[T]): lent T =
  for i in 1..<results.len: results[0] = intersection(results[0], results[i])
  results[0]

proc union*[T](results: var seq[T]): lent T =
  for i in 1..<results.len: results[0] = union(results[0], results[i])
  results[0]

proc idf*(N, f_t: auto): float32 = ln(N.float / f_t.float)

proc pushOrReplace*[T](hq: var HeapQueue[T], x: T, top=10) =
  if hq.len < top:
    hq.push x
  elif x > hq[0]:
    discard hq.replace x

iterator popAscending*[T](hq: var HeapQueue[T]): T =
  while hq.len > 0:
    yield hq.pop

type  #XXX should flesh this out & integerate
  TermFreq*   = enum tfBool,    ## if rawCount > 0: 1 else: 0
                     tfNatural, ## raw count of terms in doc/query
                     tfLog,     ## 1 + ln(rawCount)
                     tfAug,     ## (1 + rawCount/max_t(rawCount))/2
                     tfLogAve   ## (1 + ln(rawCount))/(1+ln(ave_tInD(raw))
  DocFreq*    = enum dfNone,    ## 1.0
                     dfT,       ## IDF ln(N/df_t)
                     dfProb     ## max(0, ln((N-df_t)/df_t)
  WeightNorm* = enum wnNone,    ## 1.0
                     wnCosine,  ## 1/sqrt(sum(w^2))
                     wnPivot,   ## u^-1
                     wnByte     ## len^-alpha, alpha on (0,1)

proc w_t*(k: TermFreq): float = discard

proc w_d*(k: DocFreq): float = discard

proc norm*(k: WeightNorm): float = discard
