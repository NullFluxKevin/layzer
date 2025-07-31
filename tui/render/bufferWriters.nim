# TODO: doAssert error messages

import unicode

import doubleBuffer
import layoutEngine


type
  Symbol* = distinct Rune


proc toSymbol*(s: string): Symbol = 
  doAssert s.runeLen == 1, "Error: Symbol must be a single rune"
  doAssert displayWidth(s) == 1

  s.runeAt(0).Symbol


proc `$`*(symbol: Symbol): string =
  $symbol.Rune


proc repeat*(symbol: Symbol, count: Natural): string = 
  repeat(symbol.Rune, count)

proc writeHorizontal*(buffer: Buffer, content: string, styles: SpanStyles = defaultSpanStyles) =
  doAssert buffer.height == 1

  buffer.writeToLine(0, content, styles)


proc writeVertical*(buffer: Buffer, content: string, styles: SpanStyles = defaultSpanStyles) =
  doAssert buffer.width == 1
  doAssert buffer.height >= content.runeLen

  for index, rune in content.toRunes.pairs:
    buffer.writeToLine(index, $rune, styles)


proc writeSymbol*(buffer: Buffer, symbol: Symbol, styles: SpanStyles = defaultSpanStyles) =
  doAssert buffer.width == 1 and buffer.height == 1
  
  buffer.writeToLine(0, $symbol, styles)


when isMainModule:
  let
    lineH = initRect(0, 0, 30, 1)
    lineV = initRect(2, 2, 1, 20)
    cell = initRect(10, 10, 1, 1)

  var
    bufferH = newBuffer(lineH)
    bufferV = newBuffer(lineV)
    bufferCell = newBuffer(cell)

  bufferH.writeHorizontal("→漢😀")
  bufferH.render()

  # bufferH.writeVertical("漢😀") Will fail because vertical line has width of 1 and those unicode chars have width of 2
  bufferV.writeVertical("Hello World")
  bufferV.render()

  bufferCell.writeSymbol("─".toSymbol)
  bufferCell.render()

  echo("\r\n")
  echo("\r\n")
