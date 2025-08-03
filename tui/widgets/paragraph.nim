import algorithm
import strutils
import unicode
import terminal
import tables
import sequtils

import tui/render/doubleBuffer
import layoutEngine

type
  Paragraph = string
  ParagraphLines = seq[string]


proc toLinesOfChars(paragraph: Paragraph, lineWidth: Natural, delimiters: set[char] = Whitespace): ParagraphLines =
  
  var
    chunk: string = ""

  for rune in paragraph.toRunes:
    let runeWidth = displayWidth($rune)

    if chunk.displayWidth + runeWidth <= lineWidth:
      chunk.add(rune)
    else:
      result.add(chunk)

      chunk = $rune
          

  if chunk.len != 0:
    result.add(chunk)


proc toLinesOfWords(paragraph: Paragraph, lineWidth: Natural, delimiters: set[char] = Whitespace): ParagraphLines =

  let space = " "

  var
    chunk = ""
    isFirstWord = true
   
  for word in paragraph.split(delimiters):
    doAssert word.displayWidth <= lineWidth, "Error: A word in the paragraph is longer than the given line width"

    if chunk.displayWidth + word.displayWidth + space.len <= lineWidth:
      if isFirstWord:
        chunk = word
        isFirstWord = false
      else:
        chunk &= space & word
    else:
      result.add(chunk)

      chunk = word

        
  if chunk.len != 0:
    result.add(chunk)


proc toKeywordSpans(rect: Rect, content: string, keyword: string, keywordStyles: SpanStyles, styles: SpanStyles = defaultSpanStyles): seq[Span] = 

  let temp = content.split(keyword)

  var parts: seq[string] = @[]
  for i, t in temp:
    parts.add(t)
    if i != temp.high:
      parts.add(keyword)

  var constraints: seq[Constraint] = @[]

  for j, part in parts:
    if j == parts.high:
      # Line width <= buffer width, not strictly ==
      constraints.add(minLength(part.displayWidth))
    else:
      constraints.add(fixedLength(part.displayWidth))


  let rects = rect.splitLine(constraints)

  for (rect, part) in zip(rects, parts):
    var currentStyles = styles
    if part == keyword:
      currentStyles = keywordStyles

    let span = toSpan(rect, part, currentStyles)
    result.add(span)


# Byte index to Rune index map
proc BRIMap(text: string): Table[Natural, Natural] = 

  var byteCount = 0
  for runeIndex, rune in text.toRunes:

    let byteLen = graphemeLen($rune, 0)
    
    for byteIndex in 0 ..< byteLen:
      result[byteCount] = runeIndex
      inc byteCount
     

# DO NOT! DO NOT!! TOUCH THIS CODE! Six hours of juggling byte length, rune length and display width! You break it, you buy it!
type ByteIndex = Natural
proc keywordIndices(keyword, text: string, byteRuneIndexMap: Table[Natural, Natural], startByteIndex: Natural = 0): seq[ByteIndex] = 
  let runes = text.toRunes
  # BYTE!!! INDEX!!!
  let byteIndex = text.find(keyword, startByteIndex)


  if byteIndex == -1:
    return @[]

  let
    rightNeighborByteIndex = byteIndex + keyword.len

  var isLeftSideClean = false
  if byteIndex == startByteIndex:
    isLeftSideClean = true
  elif byteIndex > startByteIndex and not runes[byteRuneIndexMap[byteIndex] - 1].isAlpha:
    isLeftSideClean = true

  let isAtTheEnd = rightNeighborByteIndex == text.len
  var isRightSideClean = false
  if isAtTheEnd:
    isRightSideClean = true

  elif rightNeighborByteIndex < text.len and not runes[byteRuneIndexMap[rightNeighborByteIndex]].isAlpha:
    isRightSideClean = true

  # if keyword == "sint":
  #   echo isLeftSideClean
  #   echo isRightSideClean
  #   echo "byteIndex: ", byteIndex
  #   echo "startByteIndex: ", startByteIndex
  #   echo byteRuneIndexMap[byteIndex]

  if isLeftSideClean and isRightSideClean:
    result.add(byteIndex)

  if not isAtTheEnd:
    result = result.concat(
      keyword.keywordIndices(text, byteRuneIndexMap, rightNeighborByteIndex) 
    )
      

# IMPORTANT: Impossible to make case insensitive version because how string hashing works in HashTable
# 
# DO NOT! DO NOT!! TOUCH THIS CODE! Six hours of juggling byte length, rune length and display width! You break it, you buy it!
proc drawParagraphLines(buffer: Buffer, lines: ParagraphLines, keywordStyles: Table[string, SpanStyles], styles: SpanStyles = defaultSpanStyles) =

  doAssert lines.len <= buffer.height


  for i, line in lines:
    var hasKeyword = false

    var final: seq[string] = @[]

    for keyword in keywordStyles.keys:

      if line.contains(keyword):

        var
          parts: seq[string] = @[]
          start = 0

        let
          briMap = BRIMap(line)
          indices = keyword.keywordIndices(line, briMap)
        if indices.len == 0:
          continue

        hasKeyword = true

        for index in indices:
          if index != 0:
            let beforeKeyword = line[start ..< index] 
            parts.add(beforeKeyword)
          parts.add(keyword)
          start = index + keyword.len

         
        if start < line.high:
          let lastPart = line[start ..< line.len]
          parts.add(lastPart)

        var constraints: seq[Constraint] = @[]
        for i, part in parts:
          if i == parts.high:
            constraints.add(minLength(part.displayWidth))
          else:
            constraints.add(fixedLength(part.displayWidth))

        let rect = buffer.getLineRect(i)
        let rects = layout(ldHorizontal, rect, constraints)

        echo parts
        echo()

        var spans: seq[Span] = @[]
        for (rect, part) in zip(rects, parts):
          let currStyles = keywordStyles.getOrDefault(part, styles)
          # if part == "sint":
            # echo currStyles

          spans.add(toSpan(rect, part, currStyles))
          

        buffer.setLineContent(i, spans)


    if not hasKeyword:
      buffer.writeToLine(i, line, styles)
      


proc drawParagraphLines(buffer: Buffer, lines: ParagraphLines, styles: SpanStyles = defaultSpanStyles) =
  doAssert lines.len <= buffer.height

  for i, line in lines:
    buffer.writeToLine(i, line, styles)


# when isMainModule:
#   let
#     keyword = "as"
#     words = @[
#       "as",
#       ": as",
#       "as.",
#       "assassin",
#       "assassin-as-a-service",
#       "assassin-as-a-service-as-a-joke",
#       "assassin as a service as a joke",

#     ]

#   for word in words:
#     echo keyword
#     echo word
#     echo repr keyword.keywordIndices(word)
#     echo()


when isMainModule:
  hidecursor()
  erasescreen()

  # Paragraph with wide characters
  # ############################################################################
  # let

    # emoGiraffe = "😞🦒, 😞🦒😞🦒. A paragraph of emojis, it's an emojiraph! 😞🦒😞🦒😞🦒😞🦒, emo😞, giraffe🦒, 😞emoGiraffe🦒, 😞😞🦒😞🦒😞"
    # width = 30
    # height = 5

    # rect = initRect(0, 0, width, height)

  # let
    # testTarget = "🦒emo😞"
    # briMap = BRIMap(testTarget)

    # keys = sorted(briMap.keys.toSeq)

  # for key in keys:
    # echo(key, ": ", briMap[key])

  # echo "emo".keywordIndices(testTarget, briMap)
  # echo "emo".keywordIndices(emoGiraffe, BRIMap(emoGiraffe))
  # var buffer = newBuffer(rect)

  # let lines = emoGiraffe.toLinesOfWords(buffer.width)
  # let lines = emoGiraffe.toLinesOfChars(buffer.width)


  # let keywordStyles = {
  #   "emo": initSpanStyles(fgBlue, bgDefault),
  #   "emoGiraffe": initSpanStyles(fgYellow, bgDefault, {styleBlink}),
  # }.toTable

  # buffer.drawParagraphLines(lines, keywordStyles)

     

  # Paragraph with ASCIIs
  # ############################################################################
  let
    width = 50
    height = 20

    rect = initRect(0, 0, width, height)

    paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. as. assassin. assassin-as-a-service. assassin-as-a-service-as-a-joke."     


  # echo "in".keywordIndices(paragraph)
  let keywordStyles = {
    "sint": initSpanStyles(fgBlue, bgDefault),
    "in": initSpanStyles(fgYellow, bgDefault, {styleBlink}),
    "as": initSpanStyles(fgRed, bgDefault, {styleUnderscore}),
  }.toTable
  
  var buffer = newBuffer(rect)
  let lines = paragraph.toLinesOfWords(buffer.width)
  # let lines = paragraph.toLinesOfChars(buffer.width)
  drawParagraphLines(buffer, lines, keywordStyles)

  # PROBLEM:
  # same line has two different keywords, the second keyword split the line again and override the previous keyword's styles
  # for keyword sint and in:
  # @["sint", " occaecat cupidatat non proident, sunt in"]
  # @["sint occaecat cupidatat non proident, sunt ", "in"]


  # ############################################################################
   
  # buffer.render()
  discard getch()
  erasescreen()
  showcursor()


