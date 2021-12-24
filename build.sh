#!/bin/sh
export n='/dev/null'
: ${a:='/tmp/abstracts'}    # For me, /tmp is a bind mount to /dev/shm
: ${f:='/tmp/framed'}
: ${x:=''}                  # -d:stem -d:unic -d:skipEmpty
: ${nob:='-d:useMalloc --checks:off --panics:on --passC:-flto --passL:-flto'}
: ${gc:="arc"}
: ${no:="-d:release -d:danger --gc:$gc $nob"}
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
./nim-pgo ixRankCos7       './ixRankCos7 < $f > $n' "$x"

mkdir -p /dev/shm/ix; (cd /dev/shm/ix && rm -f .)
./nim-pgo ixSave8 './ixSave8 /dev/shm/ix build <$f>$n;echo london beer|./ixSave8' "$x"
(cd /dev/shm/ix && rm -f .)

./nim-pgo ixSaveMmap9 './ixSaveMmap9 /dev/shm/ix build <$f>$n;echo london beer|./ixSaveMmap9' "$x"
(cd /dev/shm/ix && rm -f .)
