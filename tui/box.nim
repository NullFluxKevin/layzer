import unicode
import strutils
import terminal

import layoutEngine

# TODO: Bottom Title border
# TODO: Vertical Title borders

template withCursorPos(x, y: int, body: untyped) =
  let (prevX, prevY) = getCursorPos()
  setCursorPos(x, y)
  body
  setCursorPos(prevX, prevY)

type
  Box = object
    cornerTopLeft, borderTop, cornerTopRight: Rect
    borderLeft, canvas, borderRight: Rect
    cornerBottomLeft, borderBottom, cornerBottomRight: Rect

  BorderSymbols = object
    horizontal, vertical, cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: string

  TitleAlignment= enum taLowerEnd, taCenter, taHigherEnd

proc initBox(rect: Rect): Box = 
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


proc initBorderSymbols(horizontal, vertical, cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight: string): BorderSymbols = 
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

proc defaultDraw(content: string) =
  stdout.write(content)

proc drawHorizontal(rect: Rect, content: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.height == 1
  doAssert content.runeLen <= rect.width
  withCursorPos(rect.x, rect.y):
    draw(content)

proc drawVertical(rect: Rect, content: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.width == 1
  doAssert content.runeLen <= rect.height

  for i in 0 ..< rect.height:
    withCursorPos(rect.x, rect.y + i):
      draw(content)
 
proc drawSymbol(rect: Rect, content: string, draw: proc(content: string) = defaultDraw) = 
  doAssert rect.width == 1
  doAssert rect.height == 1
  doAssert content.runeLen == 1

  withCursorPos(rect.x, rect.y):
    draw(content)


proc drawCorners(box: Box, symbols: BorderSymbols = defaultBorder) = 
  drawSymbol(box.cornerTopLeft, symbols.cornerTopLeft)
  drawSymbol(box.cornerTopRight, symbols.cornerTopRight)
  drawSymbol(box.cornerBottomLeft, symbols.cornerBottomLeft)
  drawSymbol(box.cornerBottomRight, symbols.cornerBottomRight)


proc drawLeftBorder(box: Box, symbols: BorderSymbols = defaultBorder) = 
  drawVertical(box.borderLeft, symbols.vertical)

proc drawRightBorder(box: Box, symbols: BorderSymbols = defaultBorder) = 
  drawVertical(box.borderRight, symbols.vertical)

proc drawTopBorder(box: Box, symbols: BorderSymbols = defaultBorder) = 
  let horizontalBorder = symbols.horizontal.repeat(box.borderTop.width).join
  drawHorizontal(box.borderTop, horizontalBorder)

proc drawBottomBorder(box: Box, symbols: BorderSymbols = defaultBorder) = 
  let horizontalBorder = symbols.horizontal.repeat(box.borderTop.width).join
  drawHorizontal(box.borderBottom, horizontalBorder)

proc drawTitleBorderHorizontal(border: Rect, title: string, alignment: TitleAlignment = taLowerEnd, minLengthEachEnd:Natural = 2, minTitleSpacePadding:Natural = 1, symbols: BorderSymbols = defaultBorder) = 

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


  drawHorizontal(leftSection, symbols.horizontal.repeat(leftSection.width))
  drawHorizontal(titleSection, paddedTitle)
  drawHorizontal(sections[2], symbols.horizontal.repeat(rightSection.width))


proc drawTopTitleBox(box: Box, title: string, alignment: TitleAlignment = taLowerEnd) = 
  box.drawCorners
  box.borderTop.drawTitleBorderHorizontal(title, alignment)
  box.drawBottomBorder
  box.drawLeftBorder
  box.drawRightBorder


proc drawDefaultBox(box: Box) = 
  box.drawCorners
  box.drawTopBorder
  box.drawBottomBorder
  box.drawLeftBorder
  box.drawRightBorder

    
when isMainModule:
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
        Constraint(kind: ckLength, length: 5),
        Constraint(kind: ckPercent, percent: 40),
        Constraint(kind: ckPercent, percent: 60),
      ]


      cols = layout(ldHorizontal, outerBox.canvas, colsConstraints)
      sidebar = cols[0]
      main = cols[1]
      # mainBox = initBox(main)
      rows = layout(ldVertical, main, rowsConstraints)

    # echo "Outer Box: ", rect
    outerBox.drawTopTitleBox("Left Title")

    for i, row in rows:
      if i == 0:
        initBox(row).drawTopTitleBox("Centered Title", alignment=taCenter)
      elif i == 1:
        initBox(row).drawTopTitleBox("Right Title", alignment=taHigherEnd)
      else:
        drawDefaultBox(initBox(row))

    drawDefaultBox(initBox(sidebar))
 

    discard getch()

    eraseScreen()
    setCursorPos(0, 0)
  finally:
    showCursor()

