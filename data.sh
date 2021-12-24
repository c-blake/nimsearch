#!/bin/sh
: ${URI_STUB:="https://dumps.wikimedia.org/enwiki/latest"}
: ${BASE:=${1:-"enwiki-latest-abstract.xml"}}
[ -e $BASE.gz -o -e $BASE.zs ] || wget $URI_STUB/$BASE.gz
if [ -e $BASE.zs ]; then
    catz $BASE.zs
else
    catz $BASE.gz
fi
