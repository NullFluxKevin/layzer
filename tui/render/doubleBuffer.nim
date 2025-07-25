import colors
import terminal
import strformat
import unicode

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


when isMainModule:
  let rect = initRect(0, 0, 20, 1)

  let spanTrueColor = toSpan(rect, "True Color", initSpanColors(colPurple, colBurlyWood), {styleBlink, styleUnderscore})
  let spanANSIColor= toSpan(rect, "ANSI Color", initSpanColors(fgYellow, bgBlack))

  echo $spanTrueColor
  echo $spanANSIColor
  
