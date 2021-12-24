#!/bin/sh
export n="/dev/null"

: ${a:="/tmp/abstracts"}    # For me, /tmp is a bind mount to /dev/shm
: ${f:="/tmp/framed"}
: ${ix:="/dev/shm/ix"}

[ -r $a ] ||
  ./data.sh|grep -v '^<sublink linktype' > $a

tm=/usr/bin/time; exec 2>&1 # time writes to stderr

echo BENCHMARKING.
echo ixAllInOneEasy1 ; $tm ./ixAllInOneEasy1  <$a >$n
echo ixAllInOnePyIsh2; $tm ./ixAllInOnePyIsh2 <$a >$n
echo ixAllInOneUTF8_3; $tm ./ixAllInOneUTF8_3 <$a >$n
echo wikipa          ; $tm ./wikipa           <$a >$f
echo ixEasy4         ; $tm ./ixEasy4          <$f >$n
echo ixFull5         ; $tm ./ixFull5          <$f >$n
echo ixMerge6        ; $tm ./ixMerge6         <$f >$n
echo ixRankCos7      ; $tm ./ixRankCos7       <$f >$n
mkdir -p $ix; (cd $ix && rm -f .)
echo ixSave8         ; $tm ./ixSave8 $ix build <$f >$n
# (cd $ix && rm -f .) # leave around for query testing
