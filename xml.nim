import sets, streams, parsexml

iterator xml*(f: File, name: string, elements: HashSet[string], dataKinds =
              {xmlCharData,xmlWhitespace,xmlCData,xmlEntity}): (string,string) =
  var t = ""
  var x: XmlParser                      # yield (elName, innerText) for elements
  open(x, f.newFileStream, name)
  x.next                                # get to first XML element
  while x.kind != xmlEOF:
    if x.kind in {xmlElementStart, xmlElementOpen} and
       (var e = x.elementName; e in elements):
      if x.kind == xmlElementOpen:
        x.next
        while x.kind != xmlElementClose: x.next
      x.next                            # skip ElementStart|ElementClose
      t.setLen 0                        # trunc yielded
      while not (x.kind == xmlElementEnd and x.elementName == e):
        if x.kind in dataKinds:         # accumulate all data in `t`
          t.add x.charData
        x.next
      yield (e, t)
    else:
      x.next
  x.close
