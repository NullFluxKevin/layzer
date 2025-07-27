import os
import colors
import terminal
import strformat
import sequtils
import math
import sets

import layoutEngine


type
  SpanColorsKind = enum
    sckTrueColor, sckANSIColor

  SpanColors = object
    case kind: SpanColorsKind
    of sckTrueColor:
      fgTrueColor, bgTrueColor: Color
    of sckANSIColor:
      fg: ForegroundColor
      bg: BackgroundColor
      fgBright, bgBright: bool

  Span = object
    rect: Rect
    content: string
    colors: SpanColors
    styles: set[Style]


template ansiBackgroundColorCode*(bg: BackgroundColor,
                                  bright: bool = false): string =
  ansiStyleCode(bg.int + bright.int * 60)


proc initSpanColors(fg: Color, bg: Color): SpanColors = 
  SpanColors(kind: sckTrueColor, fgTrueColor: fg, bgTrueColor: bg)


proc initSpanColors(fg: ForegroundColor, bg: BackgroundColor, fgBright: bool = false, bgBright: bool = false): SpanColors = 
  SpanColors(kind: sckANSIColor, fg: fg, bg: bg, fgBright: fgBright, bgBright: bgBright)


proc `$`(colors: SpanColors): string = 
  case colors.kind:
  of sckTrueColor:
    result.add(ansiForegroundColorCode(colors.fgTrueColor))
    result.add(ansiBackgroundColorCode(colors.bgTrueColor))
  of sckANSIColor:
    result.add(ansiForegroundColorCode(colors.fg, colors.fgBright))
    result.add(ansiBackgroundColorCode(colors.bg, colors.bgBright))
        

proc toSpan(rect: Rect, content: string, colors: SpanColors, styles: set[Style] = {}): Span = 

  doAssert rect.height == 1, fmt"Error: Spans are rects of height 1. Height of given rect: {rect.height}"

  # ========================================================================
  # TODO: Proper Unicode Character Width Handling
  #
  # Currently, the code uses `content.len` (byte length) for span width checks,
  # which does NOT correctly handle multi-byte or wide Unicode characters.
  #
  # Attempted to use C's `wcwidth()` via Nim FFI to determine the display width
  # of characters, but it consistently returns -1 for wide characters like '你',
  # despite correct locale settings and environment.
  #
  # This unreliable behavior on the target platform makes libc's `wcwidth` unusable.
  #
  # Future plans:
  # - Investigate or port a pure Nim implementation of `wcwidth` or similar,
  #   based on Unicode East Asian Width properties, to avoid dependency on libc.
  # - Alternatively, temporarily restrict input to ASCII and single-width chars,
  #   with a clear comment about this limitation.
  #
  # This feature is critical for proper rendering and cursor positioning in the TUI,
  # but deferred for now to focus on core buffer and rendering infrastructure.
  #
  # ========================================================================
  doAssert content.len <= rect.width, fmt"Error: Content longer than span width. Span width: {rect.width}; Content length: {content.len}; Content: {content}"

  Span(rect: rect, content: content,colors: colors, styles: styles)


proc `$`(span: Span): string =
  for style in span.styles:
    result.add(ansiStyleCode(style))

  result.add($span.colors)

  result.add(span.content)
  result.add(ansiResetCode)


const stylePrefix = "\e["

type
  Buffer = object
    lines: seq[Rect]
    front, back: seq[seq[Span]]
    changedLines: Hashset[Natural]


proc initBuffer(rect: Rect): Buffer =
  var constraints: seq[Constraint] = @[]
  for _ in 0..<rect.height:
    constraints.add(Constraint(kind: ckLength, length: 1))
    
  result.lines = layout(ldVertical, rect, constraints)
  result.front = newSeq[seq[Span]](rect.height)
  result.back = newSeq[seq[Span]](rect.height)
  result.changedLines = HashSet[Natural]()


proc `[]`(buffer: Buffer, lineNumber: int): Rect = 
  buffer.lines[lineNumber]


proc width(buffer: Buffer): Natural =
  buffer[0].width


proc height(buffer: Buffer): Natural =
  buffer[0].height


proc onLine(buffer: var Buffer, lineNumber: int, spans: varargs[Span]) =
  let widthSum = spans.map(proc(span: Span): Natural = span.rect.width).sum

  doAssert widthSum <= buffer.width, "Error: Spans exceed line length"
  buffer.back[lineNumber] = spans.toSeq
  buffer.changedLines.incl(lineNumber)


proc cursorPositionPrefix(x, y: Natural): string = 
  fmt"{stylePrefix}{y+1};{x+1}f"


proc addNewLineSuffix(s: var string) =
  s &= "\r\n"
  

proc dumpBuffer(buffer: Buffer, dumpBackBuffer: bool): string =
  let toDump = if dumpBackBuffer: buffer.back else: buffer.front

  for line in toDump:
    if line.len == 0:
      result.addNewLineSuffix()
      continue

    for span in line:
      result.add($span)

    result.addNewLineSuffix()


proc renderFrame(buffer: var Buffer): string =
  while buffer.changedLines.len > 0:

    let
      lineNumber = buffer.changedLines.pop
      line = buffer[lineNumber]

    result.add(cursorPositionPrefix(line.x, line.y))

    for span in buffer.back[lineNumber]:
      result.add($span)
    
    result.addNewLineSuffix()


  (buffer.front, buffer.back) = (buffer.back, buffer.front)

      
when isMainModule:
  let rect = initRect(10, 10, 30, 10)
  
  var buffer = initBuffer(rect)

  let
    line0 = buffer[0]
    counterLine = buffer[1]
    line2 = buffer[2]

    span0Content = "True Color"
    span1Content = "ANSI Color"
    counterLabel = "Counted: "
    counterSuffix = "time(s)"

    line0Rects = layout(ldHorizontal, line0, @[
      Constraint(kind: ckMinLength, minLength: span0Content.len),
    ])

    line2Rects = layout(ldHorizontal, line2, @[
      Constraint(kind: ckMinLength, minLength: span1Content.len),
    ])


    counterLineRects = layout(ldHorizontal, counterLine, @[
      Constraint(kind: ckLength, length: counterLabel.len),
      Constraint(kind: ckMinLength, minLength: 0),
      Constraint(kind: ckLength, length: counterSuffix.len),
    ])

    span0Rect = line0Rects[0]
    span1Rect = line2Rects[0]

  let spanTrueColor = toSpan(span0Rect, span0Content, initSpanColors(colPurple, colBurlyWood), {styleBlink, styleUnderscore})

  let spanANSIColor = toSpan(span1Rect, span1Content, initSpanColors(fgYellow, bgBlack))

  let counterLabelSpan = toSpan(counterLineRects[0], counterLabel, initSpanColors(fgDefault, bgDefault))

  let counterSuffixSpan = toSpan(counterLineRects[2], counterSuffix, initSpanColors(fgDefault, bgDefault))

  buffer.onLine(0, spanTrueColor)
  buffer.onLine(2, spanANSIColor)

  for i in 0 ..< 100000:
    let counterText = fmt" {$i} "
    let counterSpan = toSpan(counterLineRects[1], counterText, initSpanColors(fgDefault, bgDefault))
    buffer.onLine(1, counterLabelSpan, counterSpan, counterSuffixSpan)
    
    echo buffer.renderFrame()
    # sleep(10)
