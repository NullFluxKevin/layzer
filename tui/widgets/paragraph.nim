import strutils
import unicode
import terminal
import tables
import sequtils
import deques
import sets

import tui/render/doubleBuffer
import layoutEngine


# ========================================================================
# ==================== !!! Complexity Hazard Zone !!! ==================== 
# ========================================================================
# I spent at least 20 hours to make this section work.
# DO NOT TOUCH THIS SECTION UNLESS YOU HAVE TO.
# YOU HAVE BEEN WARNED.
# 
# 
# 
# Definitions:
# ===================================================
# Symbol is a single character that visually makes sense to its viewer.
#   e.g. A number, a letter, an emoji, a CJK character.
# 
# Keyword is a consecutive sequence of symbols whose adjacent symbols are not alphabetic symbols (deteremined by Nim's Rune.isAlpha).
# 
# 
# What I was trying to do:
# ===================================================
# Separated styles for selected "keywords" in a paragraph. 
# 
# 
# The problems:
# ===================================================
# 
# Unreliable keyword detection:
# ==============================
# string.contains(substring) for keyword detection will cause false positive when the keyword is a partial match (reporting "income" contains the keyword "in").
#
# 
# Styles overwrite on lines contain multiple keywords:
# ==============================
# For example, let's assume a line contains keywords A and B, we want different styles for them.
# If keyword A is processed first, spans are constructed for A, the substring on its left and the substring on its right, with keyword A's styles and default paragraph styles, respectively. Then keyword B is checked, the spans are recreated with B as the keyword, overwitting what's done for A.
#   
# string.contains will also cause this because of it's false positive, the line is considered containing multiple keywords even when it does not.
#
#
# My solutions:
# ===================================================
# A reliable keyword detection mechanism using my definition of keywords.
# 
# Split the line to chunks using a keyword, and check chunks agains other keywords, repeat until all the chunks are either keywords or do not contain keywords.
#
# 
# The obstacle: Byte VS. Rune
# ===================================================

# To be able to correctly identify a keyword inside a string, I have to figure out what are its adjacent symbols. 
# 
# Symbols have three different types of length: byte length, rune length, and display width.
# 
# That in turn makes strings also have these types of length.
#
# For ASCII, these are the same and are all 1. But for Unicode, they could be different. 
# 
# I can find the byte index of the keyword using string.find, but there is no way to know how many bytes the adjacent symbols have. And there is no string.find to return the rune index. So I can't retrieve the adjacent symbols.
# 
# 
# How to overcome:
# ==============================
# Figure out how to to do byte index and rune index conversion on a string.
# 
# The current implementation builds a byte index to rune index map on a give string, for multi-byte symbols, each byte index points to the same rune index.
# 
# 
# The obstacle: Same keyword, multiple times
# ===================================================
# How to overcome:
# ==============================
# To extract all the indices of a keyword in a given text, I need to find the keyword, find the byte index of the remaining substring on its right, check the keyword on that substring.
#
# The current implementation uses recursion.
# 
# 
# The Final Boss: Exponential check-and-split branching
# ===================================================
# For each chunk that is not a keyword, every keyword is checked against it. If the chunk contains a keyword, it is split, and new chunks are added to the keyword checking queue.
#
# Yeah, the complexity is bad. Both the time/space complexity and the code complexity.
# 
# Read the comment in the proc for implementation details.
# 
# It works for now, I'll see this goes when the paragraph gets longer in an app.
#
# An idea I had when I was designing this is to use a binary tree. Each keyword is a root node of a subtree, left and right points to substrings next to it. But that would also need traversal which uses either recursion or stack/queue. And there is also the problem of inbalanced trees. That seemed more complicated, so I just went for a queue implementation directly. I could be wrong, maybe that's the right/better way to do it.
#   
#  
# Important limitations:
# ===================================================
# Keyword matches spanning lines
# ==============================
# When treating the paragragh as lines of chars, if a keyword is split to two lines, it won't be highlighted.
# 
# For example, keyword "emoGiraffe" with "emoG" at the end of the line and "iraffe" at the beginning of the next.
#
# A possible solution is to implement a new ParagraphLines parsing logic forcing keywords to be on the same line while the rest can remain stream of chars. Could be useful for keywords in paragraphs in CJK.
#
# 
# Keyword within a sequence of chars from different languages and/or emojis
# ==============================
# The keyword with in such sequence can not be detected, thus can't be rendered with given styles.
# ========================================================================
 
 
type
  ByteIndex = Natural
  RuneIndex = Natural
  ByteRuneIndexMap = Table[ByteIndex, RuneIndex]


proc initByteRuneIndexMap(text: string): ByteRuneIndexMap = 

  var byteCount = 0
  for runeIndex, rune in text.toRunes:

    let byteLen = graphemeLen($rune, 0)
    
    for byteIndex in 0 ..< byteLen:
      result[byteCount] = runeIndex
      inc byteCount
  

proc keywordIndices(keyword, text: string, briMap: ByteRuneIndexMap, startByteIndex: ByteIndex = 0): seq[ByteIndex] = 
  let runes = text.toRunes
  # str.find returns BYTE!!! INDEX!!! ahhhh!!!!!!!!!!!!!
  # a find proc that returns the rune index would made this so much easier
  let byteIndex = text.find(keyword, startByteIndex)


  if byteIndex == -1:
    return @[]

  let rightNeighborByteIndex = byteIndex + keyword.len

  var isLeftSideClean = false
  if byteIndex == startByteIndex:
    isLeftSideClean = true
  elif byteIndex > startByteIndex and not runes[briMap[byteIndex] - 1].isAlpha:
    isLeftSideClean = true

  let isAtTheEnd = rightNeighborByteIndex == text.len
  var isRightSideClean = false
  if isAtTheEnd:
    isRightSideClean = true

  elif rightNeighborByteIndex < text.len and not runes[briMap[rightNeighborByteIndex]].isAlpha:
    isRightSideClean = true

  if isLeftSideClean and isRightSideClean:
    result.add(byteIndex)

  if not isAtTheEnd:
    result = result.concat(
      keyword.keywordIndices(text, briMap, rightNeighborByteIndex) 
    )

      
type TextChunk = object
   text: string
   isKeyword: bool
   checkedKeywords: HashSet[string]


proc initTextChunk(text: string, isKeyword: bool, checkedKeywords: Hashset[string] = initHashSet[string]()): TextChunk = 
  result.text = text
  result.isKeyword= isKeyword
  result.checkedKeywords = checkedKeywords


proc isAtomic(chunk: TextChunk, keywords: HashSet[string]): bool =
  chunk.isKeyword or chunk.checkedKeywords >= keywords
  

proc isolateKeyword(text, keyword: string): seq[TextChunk] = 

  let
    briMap = initByteRuneIndexMap(text)
    indices = keyword.keywordIndices(text, briMap)

  if indices.len == 0:
    return result

  var start = 0

  for index in indices:
    if index != 0:
      let beforeKeyword = text[start ..< index] 
      var chunk = initTextChunk(beforeKeyword, false)
      chunk.checkedKeywords.incl(keyword)
      result.add(chunk)

    result.add( initTextChunk(keyword, true) )
    start = index + keyword.len

   
  if start < text.high:
    let lastPart = text[start ..< text.len]
    var chunk = initTextChunk(lastPart, false)
    chunk.checkedKeywords.incl(keyword)
    result.add( chunk )
    

# TODO: Combine chunks that are not keywords, which will result in creating a single span with a common style for those chunks
proc isolateKeywords(text: string, keywords: openArray[string]): seq[TextChunk] = 
  
  var dq: Deque[TextChunk] = @[TextChunk(text: text)].toDeque

  let keywordsSet = keywords.toHashSet
  while true:

    var hasEveryChunkCheckedAgainstEveryKeyword = true
    let temp = dq.toSeq
    for t in temp:
      if not t.isAtomic(keywordsSet):
        hasEveryChunkCheckedAgainstEveryKeyword = false
        break
        
    if hasEveryChunkCheckedAgainstEveryKeyword:
      break

    var chunk = dq.popFirst()

    if chunk.isAtomic(keywordsSet):
      dq.addLast(chunk)
      continue
          
    for keyword in keywords:
      if chunk.checkedKeywords.contains(keyword):
        continue
        
      var parts = isolateKeyword(chunk.text, keyword)
      if parts.len == 0:
        #[
        # When the chunk does not contain a keyword.
        # We marked this keyword checked, and add it back to the deque.
        # ("contain" here means isolateKeyword does not return empty seq)
        ]#
        chunk.checkedKeywords.incl(keyword)
        dq.addLast(chunk)

      else:
        #[
        # Where the execution reaches here, the chunk is split.
        # The subchunks need to be added to the deque for checking against keywords.
        # 
        # The subchunks inherit the checked keyword hashset from the original chunk.
        # This works because it's impossible that the subchunks contains a keyword while the chunk doesn't.
        # ("contains" here means isolateKeyword does not return empty seq)
        ]#
        let checked = chunk.checkedKeywords
        for part in parts.mitems:
          part.checkedKeywords = part.checkedKeywords + checked
          dq.addLast(part)

      #[
      # Either the chunk is marked as checked against a keyword, or it is split to new chunks, it is considered "consumed".
      # We DO NOT further check other keywords against consumed chunks to prevent duplication. Hence the break at the end.
      # 
      # For example, a chunk "assassin-as-a-service" with keyword "as" and "assassin".
      # After checking for "as", subchunks "assassin-", "as", "-a-service" are added to the deque.
      # If we then check the chunk against "assassin", it will generate subchunks with duplicated content "assassin", and "-as-a-service". 
      # 
      ]#
      break
             

  #[
  # If we think the deque as a ring, the elements are in the correct order RELATIVE to its left and right neighbors.
  # 
  # We just need to rotate the deque to make the chunk that contains the beginning of the text to position 0
  ]#
  var isDequeRotated = false
  while not isDequeRotated:
    let chunk = dq.popFirst
    if text.startsWith(chunk.text):
      dq.addFirst(chunk)
      isDequeRotated = true
    else:
      dq.addLast(chunk)
      

  while dq.len > 0:
    let chunk = dq.popFirst
    result.add(chunk)


proc toKeywordsSpans(rect: Rect, content: string, keywordStyles: Table[string, SpanStyles], styles: SpanStyles = defaultSpanStyles): seq[Span] = 
  doAssert rect.height == 1

  let keywords = keywordStyles.keys.toSeq
  let parts = isolateKeywords(content, keywords)
  if parts.len == 0:
    return result

  else:
    var constraints: seq[Constraint] = @[]
    for i, part in parts:
      if i == parts.high:
        constraints.add(minLength(part.text.displayWidth))
      else:
        constraints.add(fixedLength(part.text.displayWidth))

    let rects = layout(ldHorizontal, rect, constraints)

    
    for (rect, part) in zip(rects, parts):
      let currStyles = keywordStyles.getOrDefault(part.text, styles)

      result.add(toSpan(rect, part.text, currStyles))


# ========================================================================
# ================== !!! Complexity Hazard Zone End !!! ================== 
# ========================================================================
 
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


# IMPORTANT: Impossible to make case insensitive version because how string hashing works in HashTable
proc drawParagraphLines(buffer: Buffer, lines: ParagraphLines, keywordStyles: Table[string, SpanStyles], styles: SpanStyles = defaultSpanStyles) =

  doAssert lines.len <= buffer.height

  for i, line in lines:
    let spans = toKeywordsSpans(buffer.getLineRect(i), line, keywordStyles, styles)
    if spans.len == 0:
      buffer.writeToLine(i, line, styles)
    else:
      buffer.setLineContent(i, spans)
      

proc drawParagraphLines(buffer: Buffer, lines: ParagraphLines, styles: SpanStyles = defaultSpanStyles) =
  doAssert lines.len <= buffer.height

  for i, line in lines:
    buffer.writeToLine(i, line, styles)


when isMainModule:
  hidecursor()
  erasescreen()

  let
    width = 50
    height = 20

    rect = initRect(0, 0, width, height)

    paragraph = "Lorem ipsum dolor sit amet. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. as. assassin. assassin-as-a-service. assassin-as-a-service-as-a-joke.😞🦒, 😞🦒😞🦒. A paragraph of emojis, it's an emojiraph! 😞🦒😞🦒😞🦒😞🦒, emo😞, giraffe🦒, 😞emoGiraffe🦒, 😞😞🦒😞🦒😞. 你好，emoGiraffe你好，你好emo😞🦒啊。"     


  let keywordStyles = {
    "sint": initSpanStyles(fgGreen, bgDefault),
    "in": initSpanStyles(fgMagenta, bgDefault),
    "as": initSpanStyles(fgRed, bgDefault, {styleUnderscore}),
    "assassin": initSpanStyles(fgGreen, bgDefault, {styleItalic}),
    "emo": initSpanStyles(fgBlue, bgDefault),
    "emoGiraffe": initSpanStyles(fgYellow, bgDefault, {styleBlink}),
    "😞😞": initSpanStyles(fgDefault, bgBlue, {styleUnderscore}),
    "🦒": initSpanStyles(fgDefault, bgYellow),
    "你好": initSpanStyles(fgCyan, bgDefault),
  }.toTable
  
  var buffer = newBuffer(rect)
  # let lines = paragraph.toLinesOfWords(buffer.width)
  let lines = paragraph.toLinesOfChars(buffer.width)
  drawParagraphLines(buffer, lines, keywordStyles)

   
  buffer.render()
  discard getch()
  erasescreen()
  showcursor()
