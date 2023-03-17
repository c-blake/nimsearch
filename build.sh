#!/bin/sh
export n='/dev/null'
: ${a:='/tmp/abstracts'}    # For me, /tmp is a bind mount to /dev/shm
: ${f:='/tmp/framed'}
: ${x:=''}                  # -d:stem -d:unic -d:skipEmpty
: ${nob:='-d:useMalloc --checks:off --panics:on --passC:-flto --passL:-flto'}
: ${mm:="arc"}
: ${no:="-d:release -d:danger --mm:$mm $nob"}
export nimO="$no"
export a f

[ -r $a ] ||
  ./data.sh|grep -v '^<sublink linktype'|(head -n 100003; echo '</feed>') > $a

export ccL="-ldl -lm -lstemmer"

./nim-pgo ixAllInOneEasy1  './ixAllInOneEasy1  < $a > $n'
./nim-pgo ixAllInOnePyIsh2 './ixAllInOnePyIsh2 < $a > $n'
./nim-pgo ixAllInOneUTF8_3 './ixAllInOneUTF8_3 < $a > $n'
.
./nim-pgo wikipa           './wikipa           < $a > $f' "$x"
.                         
./nim-pgo ixEasy4          './ixEasy4    < $f > $n' "$x"
./nim-pgo ixFull5          './ixFull5    < $f > $n' "$x"
./nim-pgo ixMerge6         './ixMerge6   < $f > $n' "$x"
./nim-pgo ixOrdered7       './ixOrdered7 < $f > $n' "$x"
./nim-pgo ixRankCos8       './ixRankCos8 < $f > $n' "$x"

mkdir -p /dev/shm/ix; (cd /dev/shm/ix && rm -f .)
./nim-pgo ixSaveBasic9 './ixSaveBasic9 /dev/shm/ix build <$f>$n;echo london beer|./ixSaveBasic9' "$x"
(cd /dev/shm/ix && rm -f .)

./nim-pgo ixSaveMmapA './ixSaveMmapA /dev/shm/ix build <$f>$n;echo london beer|./ixSaveMmapA' "$x"
(cd /dev/shm/ix && rm -f .)
