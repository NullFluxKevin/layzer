import strutils
import unicode
import terminal

import tui/render/doubleBuffer
import layoutEngine


proc drawParagraphAsLinesOfChars(buffer: Buffer, paragraph: string, styles: SpanStyles = defaultSpanStyles) =
  
  var
    lines: seq[string] = @[]
    chunk: string = ""


  for rune in paragraph.toRunes:
    let runeWidth = displayWidth($rune)

    if chunk.displayWidth + runeWidth <= buffer.width:
      chunk.add(rune)
    else:
      lines.add(chunk)

      chunk = $rune
      
      doAssert lines.len <= buffer.height, "Error: Not enough lines in the buffer for the paragraph"
          
  if chunk.len != 0:
    lines.add(chunk)
    doAssert lines.len <= buffer.height, "Error: Not enough lines in the buffer for the paragraph"

  for i, line in lines:
    buffer.writeToLine(i, line, styles)


proc drawParagraphAsLinesOfWords(buffer: Buffer, paragraph: string, styles: SpanStyles = defaultSpanStyles) =

  let space = " "

  var
    chunk = ""
    lines: seq[string] = @[]
    isFirstWord = true
   
  for word in paragraph.split(space):
    doAssert word.displayWidth <= buffer.width, "Error: A word in the paragraph is longer than the line in the buffer"

    if chunk.displayWidth + word.displayWidth + space.len <= buffer.width:
      if isFirstWord:
        chunk = word
        isFirstWord = false
      else:
        chunk &= space & word
    else:
      lines.add(chunk)

      chunk = word

      doAssert lines.len <= buffer.height, "Error: Not enough lines in the buffer for the paragraph"
        
  if chunk.len != 0:
    lines.add(chunk)
    doAssert lines.len <= buffer.height, "Error: Not enough lines in the buffer for the paragraph"

  for i, line in lines:
    buffer.writeToLine(i, line, styles)



when isMainModule:
  hidecursor()
  erasescreen()

  # Paragraph with wide characters
  # ############################################################################
  let

    emoGiraffe = "😞🦒, 😞🦒😞🦒. A paragraph of emojis, it's an emojiraph! 😞🦒😞🦒😞🦒😞🦒, emo😞, giraffe🦒, 😞emoGiraffe🦒, 😞😞🦒😞🦒😞"

    width = 30
    height = 5

    rect = initRect(0, 0, width, height)

  var buffer = newBuffer(rect)

  drawParagraphAsLinesOfChars(buffer, emoGiraffe)
  # drawParagraphAsLinesOfWords(buffer, emoGiraffe)
   

  # Paragraph with ASCIIs
  # ############################################################################
  # let
  #   width = 30
  #   height = 20

  #   rect = initRect(0, 0, width, height)

  #   paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."     

  # var buffer = newBuffer(rect)
  # drawParagraphAsLinesOfChars(buffer, paragraph)
  # drawParagraphAsLinesOfWords(buffer, paragraph)
   

  # ############################################################################
   
  buffer.render()
  discard getch()
  erasescreen()
  showcursor()


