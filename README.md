The basic idea is covered in `ixAllInOneEasy1.nim`.  With that understood, one
can add concept-level features like word stemming as well as systems-level
optimizations.  (To use stemming, snowball-stemmer must be installed.)

As many such features are added, index creation & query code grows dependencies
on same-repo modules such as `xml.nim` which may be of broader interest to
people using the stdlib XML parser and `pack.nim` which can also serve as a
simple, self-contained key-value store.  (If retaining "updatability" of the
index were more important than space efficiency/memory density then instead
of `pack.nim`, the techniques of https://github.com/c-blake/suggest would be
appropriate which keeps a persistent external hash table to lists of wildly
varying length in Nim `MemFile`s.)

There is a script called `diffs.sh` that shows a set of interesting changes
and some miscellaneous results, build/bench scripts/patches.  I had originally
planned to write some good exposition of all of these individual diffs, but oh
well.  Many are small.  Just run `./diffs.sh | your-diff-viewer` or `diff=viewer
./diffs.sh`.  (Of course, I recommend https://github.com/c-blake/hldiff piped to
`less`, but there are many.)

Some of these scripts may assume that you have either copies or symbolic or
hard links to saved/pre-downloaded data files such as `enwiki-*`.  These files
are too big to realistically include in the repository, but ambitious readers
should have little trouble getting them using `data.sh` (and re-compressing
with parallel decompressing `zstd` to get `.zs` files if they do not want to
wait forever and a day for decompression).  `data.sh` itself also uses `catz`
from the https://github.com/c-blake/nio package.

That's about it.  This is *not* the more fully explained tutorial/article work
I had originally set out to do.  Related ideas recently arose in the
[Forum](https://forum.nim-lang.org/t/8732).  So, it seemed worth putting out
there.  If you have a specific question, raise an issue.
