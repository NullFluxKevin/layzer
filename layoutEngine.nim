import math
import sequtils
import sugar

# TODO: Use lengths to compute positions
# TODO: Build rects using lengths and positions

type
  ConstraintKind* = enum
    ckLength, ckPercent, ckRatio, ckMinLength, ckMaxLength

  PercentValue* = range[0 .. 100]

  Constraint* = object
    case kind*: ConstraintKind
    of ckLength:
      length*: Natural
    of ckPercent:
      percent*: PercentValue
    of ckRatio:
      ratio*: Natural
    of ckMinLength:
      minLength*: Natural
    of ckMaxLength:
      maxLength*: Natural

  Rect* = object
    x*, y*, width*, height*: Natural

  ConstraintIndexPairs = seq[tuple[constraint: Constraint, index: int]]

  LayoutDirection* = enum
    ldHorizontal, ldVertical


proc fixedLength*(value: Natural): Constraint = 
  Constraint(kind: ckLength, length: value)

proc percent*(value: PercentValue): Constraint = 
  Constraint(kind: ckPercent, percent: value)

proc ratio*(value: Natural): Constraint = 
  Constraint(kind: ckRatio, ratio: value)

proc minLength*(value: Natural): Constraint = 
  Constraint(kind: ckMinLength, minLength: value)

proc maxLength*(value: Natural): Constraint = 
  Constraint(kind: ckMaxLength, maxLength: value)


proc initRect*(x, y, width, height: Natural): Rect =
  Rect(x: x, y: y, width: width, height: height)


proc doAsserts(totalLength: Natural, constraints: openArray[Constraint]) = 
  let lengthConstraints = constraints.filter((cns: Constraint)->bool => cns.kind == ckLength)

  let minLengthConstraints = constraints.filter((cns: Constraint)->bool => cns.kind == ckMinLength)

  var minRequiredLength = lengthConstraints.map((cns: Constraint)->int => cns.length).sum
  minRequiredLength += minLengthConstraints.map((cns: Constraint)->int => cns.minLength).sum

  let percentConstraints = constraints.filter((cns: Constraint)->bool => cns.kind == ckPercent)

  if len(percentConstraints) != 0:
    let totalPercentage = percentConstraints.map((cns: Constraint)->int => cns.percent).sum
    doAssert totalPercentage <= 100
  
  doAssert minRequiredLength <= totalLength


proc splitLength*(totalLength: Natural, constraints: openArray[Constraint], assertNoRemaining = true): seq[Natural] = 
# [
# Length and min length constraints will always be satisfied.
# Remaining space is shared by percent constraints, then ratio constraints, then max constraints.
# If still has space left, and has at least one min length constraint, all remaining space will be added to the first min constraint. If there are no min constraints, remaining space is added to the results as an extra.
# ]

  doAsserts(totalLength, constraints)

  var
    remaining = totalLength

    percentConstraintPairs: ConstraintIndexPairs = @[]
    ratioConstraintPairs: ConstraintIndexPairs = @[]
    minLengthConstraintPairs: ConstraintIndexPairs = @[]
    maxLengthConstraintPairs: ConstraintIndexPairs = @[]

  for constraint in constraints:
    case constraint.kind:
    of ckLength:
      remaining -= constraint.length
      result.add(constraint.length)
    of ckMinLength:
      remaining -= constraint.minLength
      result.add(constraint.minLength)
      minLengthConstraintPairs.add((constraint, high(result)))
    of ckPercent:
      result.add(0)
      percentConstraintPairs.add((constraint, high(result)))
    of ckRatio:
      result.add(0)
      ratioConstraintPairs.add((constraint, high(result)))
    of ckMaxLength:
      result.add(0)
      maxLengthConstraintPairs.add((constraint, high(result)))
   

  # Percent has the highest priority to take the remaining space
  var toBeReduced: Natural = 0
  for (constraint, index) in percentConstraintPairs:
    let length = (float(remaining) * (constraint.percent.toFloat / 100)).toInt

    result[index] = length
    toBeReduced += length

  remaining -= toBeReduced
  doAssert remaining >= 0

  # Ratio constraint has the second highest priority
  if len(ratioConstraintPairs) > 0:
    let ratioGcd = ratioConstraintPairs.map((pair: tuple[constraint: Constraint, index: int])->Natural => pair.constraint.ratio).gcd

    var ratioSum = 0
    for (constraint, _) in ratioConstraintPairs.mitems:
      constraint.ratio = constraint.ratio div ratioGcd
      ratioSum += constraint.ratio

    var toBeReduced: Natural = 0
    for (constraint, index) in ratioConstraintPairs:
      let length = remaining div ratioSum * constraint.ratio
      result[index] = length
      toBeReduced += length
  
    remaining -= toBeReduced
    doAssert remaining >= 0

  # Next, try to satisfy max constraints 
  if remaining != 0 and len(maxLengthConstraintPairs) > 0:
    for (constraint, index) in maxLengthConstraintPairs:
      if remaining >= constraint.maxLength:
        result[index] = constraint.maxLength
        remaining -= constraint.maxLength

      else:
        result[index] = remaining
        remaining = 0
        break
        

  # If still has remaining space, add to the first min constraint
  if remaining != 0 and len(minLengthConstraintPairs) > 0:
    let (_, index) = minLengthConstraintPairs[0]
    result[index] += remaining
    remaining = 0


  if assertNoRemaining:
    doAssert remaining == 0
    
  # if there is no min constraint, return the remaining size
  if remaining != 0:
    result.add(remaining)
  

proc calcPositions*(origin: int, lengths: seq[Natural]): seq[int] =
  var pos = origin
  for l in lengths:
    result.add(pos)
    pos += l
  

proc layout*(direction: LayoutDirection, rect: Rect, constraints: openArray[Constraint]): seq[Rect] = 
 
  case direction:
  of ldHorizontal:
    let 
      widths = splitLength(rect.width, constraints)
      xs = calcPositions(rect.x, widths)

    for i in 0 ..< len(widths):
      let
        x = xs[i]
        width = widths[i]
      result.add(initRect(x, rect.y, width, rect.height))

  of ldVertical:
    let 
      heights = splitLength(rect.height, constraints)
      ys = calcPositions(rect.y, heights)

    for i in 0 ..< len(heights):
      let
        y = ys[i]
        height = heights[i]
      result.add(initRect(rect.x, y, rect.width, height))
   

when isMainModule:
  # In some of the following tests, the values of totalLength and percent are picked so that percent is also the size for ease of use
  block test_splitLength_length_with_remaining:
    let
      totalLength = 100

      l1 = 10
      l2 = 20

      constraints = @[
        Constraint(kind: ckLength, length: l1),
        Constraint(kind: ckLength, length: l2),
      ]

    let lengths = splitLength(totalLength, constraints)

    doAssert lengths[0] == l1
    doAssert lengths[1] == l2
    
    doAssert lengths[2] == totalLength - l1 - l2

  block test_splitLength_length_and_min:
    let
      totalLength = 100

      l1 = 10
      l2 = 20

      minLength1 = 30
      minLength2 = 20

      constraints = @[
        Constraint(kind: ckLength, length: l1),
        Constraint(kind: ckMinLength, minLength: minLength1),
        Constraint(kind: ckLength, length: l2),
        Constraint(kind: ckMinLength, minLength: minLength2),
      ]

    let lengths = splitLength(totalLength, constraints)

    doAssert lengths[0] == l1
    doAssert lengths[1] >= minLength1
    doAssert lengths[1] == totalLength - l1 - l2 - minLength2
    doAssert lengths[2] == l2
    doAssert lengths[3] == minLength2

  block test_splitLength_length_and_min_and_100_percent:
    let
      totalLength = 140

      l1 = 10
      minLength1 = 30

      percent1 = 40
      percent2 = 25
      percent3 = 35

      constraints = @[
        Constraint(kind: ckPercent, percent: percent1),
        Constraint(kind: ckLength, length: l1),
        Constraint(kind: ckPercent, percent: percent2),
        Constraint(kind: ckMinLength, minLength: minLength1),
        Constraint(kind: ckPercent, percent: percent3),
      ]

    let lengths = splitLength(totalLength, constraints)

    doAssert lengths[1] == l1
    doAssert lengths[3] == minLength1
    doAssert lengths[0] == percent1
    doAssert lengths[2] == percent2
    doAssert lengths[4] == percent3

  block test_splitLength_length_and_min_and_not_100_percent:
    let
      totalLength = 140

      l1 = 10
      minLength1 = 30

      percent1 = 40

      constraints = @[
        Constraint(kind: ckPercent, percent: percent1),
        Constraint(kind: ckLength, length: l1),
        Constraint(kind: ckMinLength, minLength: minLength1),
      ]

    let lengths = splitLength(totalLength, constraints)

    doAssert lengths[0] == percent1
    doAssert lengths[1] == l1
    doAssert lengths[2] == totalLength - percent1 - l1

  block test_splitLength_length_and_min_and_not_100_percent_and_ratio:
    let
      totalLength = 140

      l1 = 10
      minLength1 = 30

      percent1 = 40
      ratio1 = 2
      ratio2 = 4

      constraints = @[
        Constraint(kind: ckPercent, percent: percent1),
        Constraint(kind: ckLength, length: l1),
        Constraint(kind: ckRatio, ratio: ratio2),
        Constraint(kind: ckMinLength, minLength: minLength1),
        Constraint(kind: ckRatio, ratio: ratio1),
      ]

    let lengths = splitLength(totalLength, constraints)

    doAssert lengths[0] == percent1
    doAssert lengths[1] == l1
    doAssert lengths[3] == minLength1

    var remaining = (totalLength - l1 - minLength1)
    remaining -= (remaining.toFloat * percent1.toFloat / 100).toInt

    doAssert lengths[2] == ratio2 * remaining div (ratio1 + ratio2)
    doAssert lengths[4] == ratio1 * remaining div (ratio1 + ratio2)

  block test_splitLength_length_and_min_and_not_100_percent_and_max:
    let
      totalLength = 140

      l1 = 10

      minLength1 = 30

      maxLength1 = 10
      maxLength2 = 10000

      percent1 = 40

      constraints = @[
        Constraint(kind: ckPercent, percent: percent1),
        Constraint(kind: ckMaxLength, maxLength: maxLength1),
        Constraint(kind: ckLength, length: l1),
        Constraint(kind: ckMinLength, minLength: minLength1),
        Constraint(kind: ckMaxLength, maxLength: maxLength2),
      ]

    let lengths = splitLength(totalLength, constraints)

    doAssert lengths[0] == percent1
    doAssert lengths[1] == maxLength1
    doAssert lengths[2] == l1
    doAssert lengths[3] == minLength1
    doAssert lengths[4] == totalLength - l1 - minLength1 - percent1 - maxLength1


  block test_calcPositions:
    let
      origin = 10
      totalLength = 130

      length = 20
      minLength = 10
      percent = 50

    
      constraints = @[
        Constraint(kind: ckLength, length: length),
        Constraint(kind: ckPercent, percent: percent),
        Constraint(kind: ckMinLength, minLength: minLength),
      ]

      segs = splitLength(totalLength, constraints)

      positions = calcPositions(origin, segs)

    var pos = origin 
    doAssert positions[0] == pos
    pos += length
    doAssert positions[1] == pos
    pos += percent
    doAssert positions[2] == pos 


  block test_layout:
    let
      x = 10
      y = 20
      width = 150
      height = 150
      rect = initRect(x, y, width, height)

      length = 10      
      minLength1 = 20  
      minLength2 = 20  
      percent1 = 20    
      percent2 = 30    
      ratio1 = 1       
      ratio2 = 4       
      maxLength = 5    


      constraints = @[
        Constraint(kind: ckLength, length: length),
        Constraint(kind: ckMinLength, minLength: minLength1),
        Constraint(kind: ckPercent, percent: percent1),
        Constraint(kind: ckMinLength, minLength: minLength2),
        Constraint(kind: ckRatio, ratio: ratio1),
        Constraint(kind: ckMaxLength, maxLength: maxLength),
        Constraint(kind: ckRatio, ratio: ratio2),
        Constraint(kind: ckPercent, percent: percent2),
      ]

    let
      expectedHorizontal = @[
        Rect(x: 10, width: 10, y: 20, height: 150),
        Rect(x: 20, width: 20, y: 20, height: 150),
        Rect(x: 40, width: 20, y: 20, height: 150),
        Rect(x: 60, width: 20, y: 20, height: 150),
        Rect(x: 80, width: 10, y: 20, height: 150),
        Rect(x: 90, width: 0, y: 20, height: 150),
        Rect(x: 90, width: 40, y: 20, height: 150),
        Rect(x: 130, width: 30, y: 20, height: 150)
      ]
      expectedVertical = @[
        Rect(y: 20, height: 10, width: 150, x: 10),
        Rect(y: 30, height: 20, width: 150, x: 10),
        Rect(y: 50, height: 20, width: 150, x: 10),
        Rect(y: 70, height: 20, width: 150, x: 10),
        Rect(y: 90, height: 10, width: 150, x: 10),
        Rect(y: 100, height: 0, width: 150,x: 10),
        Rect(y: 100, height: 40, width: 150,x: 10),
        Rect(y: 140, height: 30, width: 150,x: 10)
      ]

      horizontalRects = layout(ldHorizontal, rect, constraints)
      verticalRects = layout(ldVertical, rect, constraints)

    doAssert horizontalRects == expectedHorizontal
    doAssert verticalRects == expectedVertical

 
