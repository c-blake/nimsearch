#!/bin/sh
for pair in 12 23 14 45 56 67 78 89 9A AB BC
do eval ${diff-"diff"} -u *[$pair].nim
done
