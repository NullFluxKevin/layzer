import colors
import terminal
import strformat
import sequtils
import math
import sets
import unicode
import posix
import strutils

import layoutEngine


export colors, terminal


proc initModule() =
  discard setlocale(LC_ALL, "")

initModule()

type WChar = int32
proc wcwidth(c: WChar): cint {.importc, cdecl, header:"<wchar.h>".}


proc displayWidth(content: string): int = 
  doAssert '\t' notin content and
    '\r' notin content and
    '\n' notin content,
    "Error: non-printable characters are not allowed. Use whitespaces or layout engine instead."

  for rune in content.toRunes:
    let charWidth = wcwidth(rune.WChar)
    doAssert charWidth >= 0, fmt"Error: Span content contains a character with unknown display width: (U+{rune.int.toHex(6)})"

    result += charWidth


type
  SpanColorsKind* = enum
    sckTrueColor, sckANSIColor

  SpanColors* = object
    case kind*: SpanColorsKind
    of sckTrueColor:
      fgTrueColor*, bgTrueColor*: Color
    of sckANSIColor:
      fg*: ForegroundColor
      bg*: BackgroundColor
      fgBright*, bgBright*: bool

  Span* = object
    rect*: Rect
    content*: string
    colors*: SpanColors
    styles*: set[Style]

  SpanRow* = seq[Span]

  Buffer* = ref object
    lines*: seq[Rect]
    front*, back*: seq[SpanRow]
    changedLines*: Hashset[Natural]

  Frame* = string


const
  stylePrefix = "\e["
  newLine = "\r\n"

  defaultTerminalColors* = SpanColors(kind: sckANSIColor, fg: fgDefault, bg: bgDefault, fgBright: false, bgBright: false)


template ansiBackgroundColorCode*(bg: BackgroundColor,
                                  bright: bool = false): string =
  ansiStyleCode(bg.int + bright.int * 60)


proc cursorPositionPrefix(x, y: Natural): string = 
  fmt"{stylePrefix}{y+1};{x+1}f"


proc addNewLineSuffix(s: var string) =
  s &= newLine
  

proc initSpanColors*(fg: Color, bg: Color): SpanColors = 
  SpanColors(kind: sckTrueColor, fgTrueColor: fg, bgTrueColor: bg)


proc initSpanColors*(fg: ForegroundColor, bg: BackgroundColor, fgBright: bool = false, bgBright: bool = false): SpanColors = 
  SpanColors(kind: sckANSIColor, fg: fg, bg: bg, fgBright: fgBright, bgBright: bgBright)


proc `$`*(colors: SpanColors): string = 
  case colors.kind:
  of sckTrueColor:
    result.add(ansiForegroundColorCode(colors.fgTrueColor))
    result.add(ansiBackgroundColorCode(colors.bgTrueColor))
  of sckANSIColor:
    result.add(ansiForegroundColorCode(colors.fg, colors.fgBright))
    result.add(ansiBackgroundColorCode(colors.bg, colors.bgBright))
        

proc toSpan*(rect: Rect, content: string, colors: SpanColors=defaultTerminalColors, styles: set[Style] = {}): Span = 

  doAssert rect.height == 1, fmt"Error: Spans are rects of height 1. Height of given rect: {rect.height}"

  let contentWidth = displayWidth(content)
  doAssert contentWidth <= rect.width, fmt"Error: Content longer than span width. Span width: {rect.width}; Content length: {content.len}; Content: {content}"

  Span(rect: rect, content: content, colors: colors, styles: styles)


proc `$`*(span: Span): string =
  for style in span.styles:
    result.add(ansiStyleCode(style))

  result.add($span.colors)

  result.add(span.content)
  result.add(ansiResetCode)


proc newBuffer*(rect: Rect): Buffer =
  result = new(Buffer)
  var constraints = repeat(Constraint(kind: ckLength, length: 1), rect.height)
    
  result.lines = layout(ldVertical, rect, constraints)
  result.front = newSeq[seq[Span]](rect.height)
  result.back = newSeq[seq[Span]](rect.height)
  result.changedLines = HashSet[Natural]()


proc getLineRect*(buffer: Buffer, lineNumber: Natural): Rect = 
  buffer.lines[lineNumber]


proc width*(buffer: Buffer): Natural =
  buffer.getLineRect(0).width


proc height*(buffer: Buffer): Natural =
  buffer.lines.len


proc setLineContent*(buffer: Buffer, lineNumber: Natural, spans: varargs[Span]) =
  let widthSum = spans.map(proc(span: Span): Natural = span.rect.width).sum

  doAssert widthSum <= buffer.width, "Error: Spans exceed line length"
  buffer.back[lineNumber] = spans.toSeq
  buffer.changedLines.incl(lineNumber)


proc dumpBuffer*(buffer: Buffer, dumpBackBuffer: bool): string =
  let toDump = if dumpBackBuffer: buffer.back else: buffer.front

  for line in toDump:
    if line.len == 0:
      result.addNewLineSuffix()
      continue

    for span in line:
      result.add($span)

    result.addNewLineSuffix()


proc buildFrame*(buffer: Buffer): Frame =
  if buffer.changedLines.len == 0:
    return ""

  while buffer.changedLines.len > 0:

    let
      lineNumber = buffer.changedLines.pop
      line = buffer.getLineRect(lineNumber)

    result.add(cursorPositionPrefix(line.x, line.y))

    for span in buffer.back[lineNumber]:
      result.add($span)
    
    result.addNewLineSuffix()

  # Note: Swapping without clearing for now
  (buffer.front, buffer.back) = (buffer.back, buffer.front)


proc splitLine*(line: Rect, constraints: openArray[Constraint]): seq[Rect] =
  doAssert line.height == 1, "Error: Lines must have height of 1."
  layout(ldHorizontal, line, constraints)


proc splitLine*(buffer: Buffer, lineNumber: Natural, constraints: openArray[Constraint]): seq[Rect] =
  buffer.getLineRect(lineNumber).splitLine(constraints)


proc writeToLine*(buffer: Buffer, lineNumber: Natural, content:string, colors: SpanColors = defaultTerminalColors, styles: set[Style] = {}) =
  let lineContent= [toSpan(buffer.getLineRect(lineNumber), content, colors, styles)]
  buffer.setLineContent(lineNumber, lineContent)
      

proc clearLine*(buffer: Buffer, lineNumber: Natural) =
  buffer.back[lineNumber].setLen(0)


proc clearBackBuffer*(buffer: Buffer) =
  for i in 0 ..< buffer.height:
    buffer.clearLine(i)

  buffer.changedLines.clear()


proc drawFrame*(frame: Frame) =
  stdout.write(frame, newLine)
  stdout.flushFile()


proc render*(buffer: Buffer) =
  drawFrame(buffer.buildFrame())


when isMainModule:
  let rect = initRect(10, 10, 30, 10)
  
  var buffer = newBuffer(rect)

  buffer.writeToLine(0, "True Color", initSpanColors(colPurple, colBurlyWood), {styleBlink, styleUnderscore})

  buffer.writeToLine(2, "ANSI Color", initSpanColors(fgYellow, bgBlack))


  let
    counterLabel = "Counted: "
    counterSuffix = "time(s)"

    counterLineRects = buffer.splitLine(1, @[
      fixedLength(counterLabel.len),
      minLength(0),
      fixedLength(counterSuffix.len)
    ])


    counterLabelSpan = toSpan(counterLineRects[0], counterLabel)
    counterSuffixSpan = toSpan(counterLineRects[2], counterSuffix)


  for i in 0 ..< 100000:
    let
      counterText = fmt" {$i} "
      counterSpan = toSpan(counterLineRects[1], counterText)

    buffer.setLineContent(1, counterLabelSpan, counterSpan, counterSuffixSpan)
    
    buffer.render()

