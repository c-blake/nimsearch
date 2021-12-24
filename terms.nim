import sets, sugar

when defined(stem):   # snowball-stemmer is available; Could also auto-probe.
  {.passl: "/usr/lib64/libstemmer.so".} # YOU MAY NEED TO ADJUST THIS!
  type sb_stemmer {.bycopy.} = object
  proc sb_stemmer_new(algo: cstring; charenc: cstring): ptr sb_stemmer
    {.importc: "sb_stemmer_new".}
  proc sb_stemmer_stem(stm: ptr sb_stemmer; word: cstring; size: cint): cstring
    {.importc: "sb_stemmer_stem".}
  proc sb_stemmer_length(stm: ptr sb_stemmer): cint
    {.importc: "sb_stemmer_length".}
  let stm = sb_stemmer_new("english", "UTF_8")
  proc stem(word: string): string =     # wrap snowball stemmer for English
    let cs = stm.sb_stemmer_stem(word, word.len.cint)
    let cn = stm.sb_stemmer_length
    result.setLen int(cn)
    copyMem result[0].addr, cs, int(cn)
else:                                   # no-op when unavailable
  template stem(word: untyped): untyped = word

when defined(unic):
  import unicode
  iterator words(text: string): string =  # basic tokenizer
    var word = ""
    var rstr = "1234567"
    var someASCII = false
    template maybeYield {.dirty.} =
      if someASCII: yield word
      word.setLen 0
      someASCII = false
    for rune in runes(text):
      let rune = rune.toLower
      fastToUTF8Copy(rune, rstr, 0, false)
      if rune.isLower:                    # Add '0'..'9' maybe with len limit?
        word.add rstr
        if rstr.len==1: someASCII = true  # Reject words with no ASCII at all
      elif word.len > 0: maybeYield
    if word.len > 0: maybeYield
else:
  iterator words(text: string): string =  # faster tokenizer
    var word = ""
    for c in text:
      if   c in {'A'..'Z'}: word.add char(ord(c) + 32)
      elif c in {'a'..'z'}: word.add c    # Add '0'..'9' maybe with len limit?
      elif word.len > 0: yield word; word.setLen 0
    if word.len > 0: yield word

const STOP = ["the", "be", "to", "of", "and", "a", "in", "that", "have", "for",
  "i", "it", "not", "on", "with", "he", "as", "you", "do", "at", "this", "but",
  "his", "by", "from", "is", "was", "or", "s", "an", "may", "new", "are", "who",
  "which", "name", "also", "has", "its", # Last bit here is Wikipedia-specific.
  "born", "birth", "place", "places", "known", "refer", "refers" ].toHashSet

let STOP_STEMMED = collect(for stop in STOP: { stem(stop) })

iterator terms*(text: string): string =
  ## yield stemmed non-stop words in `text`
  when defined(unic):
    for word in unicode.toLower(text).words:
      let word = stem(word)             # NOTE: Must stem STOPs if ix/qry stems.
      if word.len < 256 and word notin STOP_STEMMED: yield word
  else:
    for word in text.words:
      let word = stem(word)             # NOTE: Must stem STOPs if ix/qry stems.
      if word.len < 256 and word notin STOP_STEMMED: yield word
