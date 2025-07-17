import unicode
import strutils
import terminal

import layoutEngine

export layoutEngine


template withCursorPos*(x, y: int, body: untyped) =
  let (prevX, prevY) = getCursorPos()
  setCursorPos(x, y)
  body
  setCursorPos(prevX, prevY)

type
  Box* = object
    cornerTopLeft, borderTop, cornerTopRight: Rect
    borderLeft, canvas, borderRight: Rect
    cornerBottomLeft, borderBottom, cornerBottomRight: Rect

  BorderSymbols* = object
    horizontal, vertical, cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: string

  TitleAlignment* = enum
    # Given a segment, either horizontal or vertical,
    # with positions x1, x2 and y1, y2 respectively, lower end means the smaller x or y and higher end means larger x or y in x1, x2 and y1, y2.
    # For example, for a horizontal segment, lower end means the left side.
    taLowerEnd,
    taCenter,
    taHigherEnd

proc initBox*(rect: Rect): Box = 
  doAssert rect.width >= 3
  doAssert rect.height >= 3
  let
    verticalConstraints = @[
      Constraint(kind: ckLength, length: 1),
      Constraint(kind: ckLength, length: rect.height - 2),
      Constraint(kind: ckLength, length: 1),
    ]
    horizontalConstraints = @[
      Constraint(kind: ckLength, length: 1),
      Constraint(kind: ckLength, length: rect.width - 2),
      Constraint(kind: ckLength, length: 1),
    ]
    rows = layout(ldVertical, rect, verticalConstraints)
    (topRow, midRow, bottomRow) = (rows[0], rows[1], rows[2])

    topRowCols = layout(ldHorizontal, topRow, horizontalConstraints)
    midRowCols = layout(ldHorizontal, midRow, horizontalConstraints)
    bottomRowCols = layout(ldHorizontal, bottomRow, horizontalConstraints)

  (result.cornerTopLeft, result.borderTop, result.cornerTopRight) = (topRowCols[0], topRowCols[1], topRowCols[2])
  (result.borderLeft, result.canvas, result.borderRight) = (midRowCols[0], midRowCols[1], midRowCols[2])
  (result.cornerBottomLeft, result.borderBottom, result.cornerBottomRight) = (bottomRowCols[0], bottomRowCols[1], bottomRowCols[2])


proc initBorderSymbols*(horizontal, vertical, cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: string): BorderSymbols = 
  doAssert horizontal.runeLen == 1
  doAssert vertical.runeLen == 1
  doAssert cornerTopLeft.runeLen == 1
  doAssert cornerTopRight.runeLen == 1
  doAssert cornerBottomLeft.runeLen == 1
  doAssert cornerBottomRight.runeLen == 1

  BorderSymbols(
    horizontal: horizontal,
    vertical: vertical,
    cornerTopLeft: cornerTopLeft,
    cornerTopRight: cornerTopRight,
    cornerBottomLeft: cornerBottomLeft,
    cornerBottomRight: cornerBottomRight,
  )

const singleBorder = initBorderSymbols("─", "│", "┌", "┐", "└", "┘")
const doubleBorder = initBorderSymbols("═", "║", "╔", "╗", "╚", "╝")
const roundedBorder = initBorderSymbols("─", "│", "╭", "╮", "╰", "╯")
const defaultBorder = roundedBorder

proc defaultDraw*(content: string) =
  stdout.write(content)

proc drawHorizontal*(rect: Rect, content: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.height == 1
  doAssert content.runeLen == rect.width

  withCursorPos(rect.x, rect.y):
    draw(content)

proc fillHorizontal*(rect: Rect, symbol: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.height == 1
  doAssert symbol.runeLen == 1
  doAssert symbol.runeLen <= rect.width

  let content = symbol.repeat(rect.width)
  drawHorizontal(rect, content, draw)


proc drawVertical*(rect: Rect, content: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.width == 1
  doAssert content.runeLen == rect.height

  # DO NOT use runeAt(i), it returns rune at BYTE index i, not string index i
  # and runeAtPos is slow according to Nim manual
  for i, r in content.toRunes:
    withCursorPos(rect.x, rect.y + i):
      draw($r)
 

proc fillVertical*(rect: Rect, symbol: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.width == 1
  doAssert symbol.runeLen == 1
  doAssert symbol.runeLen <= rect.height

  let content = symbol.repeat(rect.height)
  drawVertical(rect, content, draw)

proc drawSymbol*(rect: Rect, content: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.width == 1
  doAssert rect.height == 1
  doAssert content.runeLen == 1

  withCursorPos(rect.x, rect.y):
    draw(content)


proc drawCorners*(box: Box, symbols: BorderSymbols = defaultBorder) = 
  drawSymbol(box.cornerTopLeft, symbols.cornerTopLeft)
  drawSymbol(box.cornerTopRight, symbols.cornerTopRight)
  drawSymbol(box.cornerBottomLeft, symbols.cornerBottomLeft)
  drawSymbol(box.cornerBottomRight, symbols.cornerBottomRight)


proc drawLeftBorder*(box: Box, symbols: BorderSymbols = defaultBorder) = 
  fillVertical(box.borderLeft, symbols.vertical)

proc drawRightBorder*(box: Box, symbols: BorderSymbols = defaultBorder) = 
  fillVertical(box.borderRight, symbols.vertical)

proc drawTopBorder*(box: Box, symbols: BorderSymbols = defaultBorder) = 
  fillHorizontal(box.borderTop, symbols.horizontal)

proc drawBottomBorder*(box: Box, symbols: BorderSymbols = defaultBorder) = 
  fillHorizontal(box.borderBottom, symbols.horizontal)

proc drawTitleBorderHorizontal*(border: Rect, title: string, alignment: TitleAlignment = taLowerEnd, minLengthEachEnd:Natural = 2, minTitleSpacePadding:Natural = 1, symbols: BorderSymbols = defaultBorder) = 

  let minSymbolLength = 2 * minLengthEachEnd + 2 * minTitleSpacePadding
  doAssert title.runeLen <= border.width - minSymbolLength

  let
    padding = " ".repeat(minTitleSpacePadding)
    paddedTitle = padding & title & padding
  
  var horizontalConstraints: seq[Constraint]
  case alignment:
  of taLowerEnd:
    horizontalConstraints = @[
      Constraint(kind: ckLength, length: minLengthEachEnd),
      Constraint(kind: ckLength, length: paddedTitle.runeLen),
      Constraint(kind: ckMinLength, minLength: minLengthEachEnd),
    ]

  of taCenter:
    let
      available = border.width - title.runeLen - minSymbolLength
      leftEndLength = available div 2

    horizontalConstraints = @[
      Constraint(kind: ckLength, length: leftEndLength + minLengthEachEnd),
      Constraint(kind: ckLength, length: paddedTitle.runeLen),
      Constraint(kind: ckMinLength, minLength: minLengthEachEnd),
    ]

  of taHigherEnd:
    horizontalConstraints = @[
      Constraint(kind: ckMinLength, minLength: minLengthEachEnd),
      Constraint(kind: ckLength, length: paddedTitle.runeLen),
      Constraint(kind: ckLength, length: minLengthEachEnd),
    ]

  let 
    sections = layout(ldHorizontal, border, horizontalConstraints)
    leftSection = sections[0]
    titleSection = sections[1]
    rightSection = sections[2]


  fillHorizontal(leftSection, symbols.horizontal)
  drawHorizontal(titleSection, paddedTitle)
  fillHorizontal(rightSection, symbols.horizontal)


proc drawTitleBorderVertical*(border: Rect, title: string, alignment: TitleAlignment = taLowerEnd, minLengthEachEnd:Natural = 2, minTitleSpacePadding:Natural = 1, symbols: BorderSymbols = defaultBorder) = 

  let minSymbolLength = 2 * minLengthEachEnd + 2 * minTitleSpacePadding
  doAssert title.runeLen <= border.height - minSymbolLength

  let
    padding = " ".repeat(minTitleSpacePadding)
    paddedTitle = padding & title & padding
  
  var verticalConstraints: seq[Constraint]
  case alignment:
  of taLowerEnd:
    verticalConstraints = @[
      Constraint(kind: ckLength, length: minLengthEachEnd),
      Constraint(kind: ckLength, length: paddedTitle.runeLen),
      Constraint(kind: ckMinLength, minLength: minLengthEachEnd),
    ]

  of taCenter:
    let
      available = border.height - title.runeLen - minSymbolLength
      topEndLength = available div 2

    verticalConstraints = @[
      Constraint(kind: ckLength, length: topEndLength + minLengthEachEnd),
      Constraint(kind: ckLength, length: paddedTitle.runeLen),
      Constraint(kind: ckMinLength, minLength: minLengthEachEnd),
    ]

  of taHigherEnd:
    verticalConstraints = @[
      Constraint(kind: ckMinLength, minLength: minLengthEachEnd),
      Constraint(kind: ckLength, length: paddedTitle.runeLen),
      Constraint(kind: ckLength, length: minLengthEachEnd),
    ]

  let 
    sections = layout(ldVertical, border, verticalConstraints)
    topSection = sections[0]
    titleSection = sections[1]
    bottomSection = sections[2]


  fillVertical(topSection, symbols.vertical)
  drawVertical(titleSection, paddedTitle)
  fillVertical(bottomSection, symbols.vertical)

proc drawTopTitleBox*(box: Box, title: string, alignment: TitleAlignment = taLowerEnd) = 
  box.drawCorners
  box.borderTop.drawTitleBorderHorizontal(title, alignment)
  box.drawBottomBorder
  box.drawLeftBorder
  box.drawRightBorder

proc drawBottomTitleBox*(box: Box, title: string, alignment: TitleAlignment = taLowerEnd) = 
  box.drawCorners
  box.drawTopBorder
  box.borderBottom.drawTitleBorderHorizontal(title, alignment)
  box.drawLeftBorder
  box.drawRightBorder

proc drawLeftTitleBox*(box: Box, title: string, alignment: TitleAlignment = taLowerEnd) = 
  box.drawCorners
  box.drawTopBorder
  box.drawBottomBorder
  box.borderLeft.drawTitleBorderVertical(title, alignment)
  box.drawRightBorder

proc drawRightTitleBox*(box: Box, title: string, alignment: TitleAlignment = taLowerEnd) = 
  box.drawCorners
  box.drawTopBorder
  box.drawBottomBorder
  box.drawLeftBorder
  box.borderRight.drawTitleBorderVertical(title, alignment)

proc drawDefaultBox*(box: Box) = 
  box.drawCorners
  box.drawTopBorder
  box.drawBottomBorder
  box.drawLeftBorder
  box.drawRightBorder

    
when isMainModule:

  doAssert terminalWidth() >= 34, "Minimul terminal width to run demo is 34"
  doAssert terminalHeight() >= 52, "Minimul terminal height to run demo is 52"
  
  proc drawDemoTitleBox(box: Box, alignment: TitleAlignment) = 
    var
      leftTitle = "Left"
      rightTitle = "Right"
      topTitle = "Top"
      bottomTitle = "Bottom"


    case alignment:
    of taCenter:
      leftTitle.add(" Center")
      rightTitle.add(" Center")
      topTitle.add(" Center")
      bottomTitle.add(" Center")
    of taLowerEnd:
      leftTitle.add(" High")
      rightTitle.add(" High")
      topTitle.add(" Left")
      bottomTitle.add(" Left")
    of taHigherEnd:
      leftTitle.add(" Low")
      rightTitle.add(" Low")
      topTitle.add(" Right")
      bottomTitle.add(" Right")

    box.drawCorners
    box.borderRight.drawTitleBorderVertical(rightTitle, alignment)
    box.borderLeft.drawTitleBorderVertical(leftTitle, alignment)
    box.borderTop.drawTitleBorderHorizontal(topTitle, alignment)
    box.borderBottom.drawTitleBorderHorizontal(bottomTitle, alignment)

  try:
    hideCursor()
    eraseScreen()
    setCursorPos(0, 0)
    
    let
      x = 3
      y = 1
      width = terminalWidth() - 2 * x
      height = terminalHeight() - 2 * y
      rect = initRect(x, y, width, height)

      outerBox = initBox(rect)

      colsConstraints = @[
        Constraint(kind: ckPercent, percent: 20),
        Constraint(kind: ckPercent, percent: 80),
      ]

      rowsConstraints = @[
        Constraint(kind: ckMinLength, minLength: 5),
        Constraint(kind: ckPercent, percent: 40),
        Constraint(kind: ckPercent, percent: 60),
      ]


      cols = layout(ldHorizontal, outerBox.canvas, colsConstraints)
      sidebar = cols[0]
      main = cols[1]
      rows = layout(ldVertical, main, rowsConstraints)

    outerBox.drawDemoTitleBox(taCenter)

    for i, row in rows:
      let box = initBox(row)

      if i == rows.high - 1:
        box.drawDemoTitleBox(taHigherEnd)

      elif i == rows.high:
        box.drawDemoTitleBox(taLowerEnd)

      else:
        box.drawDefaultBox()

    initBox(sidebar).drawDefaultBox()
 

    discard getch()

    eraseScreen()
    setCursorPos(0, 0)
  finally:
    showCursor()

