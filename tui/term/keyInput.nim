import tables
import options

import rawTerm

# Limitations:
# 
# TL;DR:
# Linux only. Support for macOS and Windows is currently out of scope.
# No mouse support (yet. Not a big fan of it, so no promises.)
# Only detects keys and mod+key combos explicitly defined in the Key enum.
# Contributions are welcome.
#
# 
# Ctrl-Shift-key combo is not supported due to OS terminal API limitations.
# These escape sequences are specific to terminal emulators.
# Extend the defaultKeyEscSeqTable for the sequences of your terminal emulator.
# The same goes for other keys.
# If a key isn't detected, run rawTerm.nim to inspect its escape sequence and extend defaultKeyEscSeqTable accordingly.
#
# 
# Less commonly used combos are not defined (yet):
# Mod+symbol like ctrl-[, alt-Tab. However, those in the ASCII table are defined.
# Mod+number like ctrl-1, alt-2

 
type
  # Key enum is mostly copied from illwill module, except Key.None and the mouse input, and with addition of Alt and AltShift key combos. Other parts are also heavily insprired by illwill.
  # illwill license: WTFPL license
  # Source code: https://github.com/johnnovak/illwill/blob/99a120f7f69868b94f5d35ce7e21dd12535de70c/illwill.nim#L67
  
  Key* {.pure.} = enum      ## Supported single key presses and key combinations

    # Special ASCII characters
    CtrlA  = (1, "CtrlA"),
    CtrlB  = (2, "CtrlB"),
    CtrlC  = (3, "CtrlC"),
    CtrlD  = (4, "CtrlD"),
    CtrlE  = (5, "CtrlE"),
    CtrlF  = (6, "CtrlF"),
    CtrlG  = (7, "CtrlG"),
    CtrlH  = (8, "CtrlH"),
    Tab    = (9, "Tab"),     # Ctrl-I
    CtrlJ  = (10, "CtrlJ"),
    CtrlK  = (11, "CtrlK"),
    CtrlL  = (12, "CtrlL"),
    Enter  = (13, "Enter"),  # Ctrl-M
    CtrlN  = (14, "CtrlN"),
    CtrlO  = (15, "CtrlO"),
    CtrlP  = (16, "CtrlP"),
    CtrlQ  = (17, "CtrlQ"),
    CtrlR  = (18, "CtrlR"),
    CtrlS  = (19, "CtrlS"),
    CtrlT  = (20, "CtrlT"),
    CtrlU  = (21, "CtrlU"),
    CtrlV  = (22, "CtrlV"),
    CtrlW  = (23, "CtrlW"),
    CtrlX  = (24, "CtrlX"),
    CtrlY  = (25, "CtrlY"),
    CtrlZ  = (26, "CtrlZ"),
    Escape = (27, "Escape"),

    CtrlBackslash    = (28, "CtrlBackslash"),
    CtrlRightBracket = (29, "CtrlRightBracket"),

    # Printable ASCII characters
    Space           = (32, "Space"),
    ExclamationMark = (33, "ExclamationMark"),
    DoubleQuote     = (34, "DoubleQuote"),
    Hash            = (35, "Hash"),
    Dollar          = (36, "Dollar"),
    Percent         = (37, "Percent"),
    Ampersand       = (38, "Ampersand"),
    SingleQuote     = (39, "SingleQuote"),
    LeftParen       = (40, "LeftParen"),
    RightParen      = (41, "RightParen"),
    Asterisk        = (42, "Asterisk"),
    Plus            = (43, "Plus"),
    Comma           = (44, "Comma"),
    Minus           = (45, "Minus"),
    Dot             = (46, "Dot"),
    Slash           = (47, "Slash"),

    Zero  = (48, "Zero"),
    One   = (49, "One"),
    Two   = (50, "Two"),
    Three = (51, "Three"),
    Four  = (52, "Four"),
    Five  = (53, "Five"),
    Six   = (54, "Six"),
    Seven = (55, "Seven"),
    Eight = (56, "Eight"),
    Nine  = (57, "Nine"),

    Colon        = (58, "Colon"),
    Semicolon    = (59, "Semicolon"),
    LessThan     = (60, "LessThan"),
    Equals       = (61, "Equals"),
    GreaterThan  = (62, "GreaterThan"),
    QuestionMark = (63, "QuestionMark"),
    At           = (64, "At"),

    ShiftA  = (65, "ShiftA"),
    ShiftB  = (66, "ShiftB"),
    ShiftC  = (67, "ShiftC"),
    ShiftD  = (68, "ShiftD"),
    ShiftE  = (69, "ShiftE"),
    ShiftF  = (70, "ShiftF"),
    ShiftG  = (71, "ShiftG"),
    ShiftH  = (72, "ShiftH"),
    ShiftI  = (73, "ShiftI"),
    ShiftJ  = (74, "ShiftJ"),
    ShiftK  = (75, "ShiftK"),
    ShiftL  = (76, "ShiftL"),
    ShiftM  = (77, "ShiftM"),
    ShiftN  = (78, "ShiftN"),
    ShiftO  = (79, "ShiftO"),
    ShiftP  = (80, "ShiftP"),
    ShiftQ  = (81, "ShiftQ"),
    ShiftR  = (82, "ShiftR"),
    ShiftS  = (83, "ShiftS"),
    ShiftT  = (84, "ShiftT"),
    ShiftU  = (85, "ShiftU"),
    ShiftV  = (86, "ShiftV"),
    ShiftW  = (87, "ShiftW"),
    ShiftX  = (88, "ShiftX"),
    ShiftY  = (89, "ShiftY"),
    ShiftZ  = (90, "ShiftZ"),

    LeftBracket  = (91, "LeftBracket"),
    Backslash    = (92, "Backslash"),
    RightBracket = (93, "RightBracket"),
    Caret        = (94, "Caret"),
    Underscore   = (95, "Underscore"),
    GraveAccent  = (96, "GraveAccent"),

    A = (97, "A"),
    B = (98, "B"),
    C = (99, "C"),
    D = (100, "D"),
    E = (101, "E"),
    F = (102, "F"),
    G = (103, "G"),
    H = (104, "H"),
    I = (105, "I"),
    J = (106, "J"),
    K = (107, "K"),
    L = (108, "L"),
    M = (109, "M"),
    N = (110, "N"),
    O = (111, "O"),
    P = (112, "P"),
    Q = (113, "Q"),
    R = (114, "R"),
    S = (115, "S"),
    T = (116, "T"),
    U = (117, "U"),
    V = (118, "V"),
    W = (119, "W"),
    X = (120, "X"),
    Y = (121, "Y"),
    Z = (122, "Z"),

    LeftBrace  = (123, "LeftBrace"),
    Pipe       = (124, "Pipe"),
    RightBrace = (125, "RightBrace"),
    Tilde      = (126, "Tilde"),
    Backspace  = (127, "Backspace"),

    # Special characters with virtual keycodes
    Up       = (1001, "Up"),
    Down     = (1002, "Down"),
    Right    = (1003, "Right"),
    Left     = (1004, "Left"),
    Home     = (1005, "Home"),
    Insert   = (1006, "Insert"),
    Delete   = (1007, "Delete"),
    End      = (1008, "End"),
    PageUp   = (1009, "PageUp"),
    PageDown = (1010, "PageDown"),

    F1  = (1011, "F1"),
    F2  = (1012, "F2"),
    F3  = (1013, "F3"),
    F4  = (1014, "F4"),
    F5  = (1015, "F5"),
    F6  = (1016, "F6"),
    F7  = (1017, "F7"),
    F8  = (1018, "F8"),
    F9  = (1019, "F9"),
    F10 = (1020, "F10"),
    F11 = (1021, "F11"),
    F12 = (1022, "F12"),

    AltA = (2001, "AltA")
    AltB = "AltB"
    AltC = "AltC"
    AltD = "AltD"
    AltE = "AltE"
    AltF = "AltF"
    AltG = "AltG"
    AltH = "AltH"
    AltI = "AltI"
    AltJ = "AltJ"
    AltK = "AltK"
    AltL = "AltL"
    AltM = "AltM"
    AltN = "AltN"
    AltO = "AltO"
    AltP = "AltP"
    AltQ = "AltQ"
    AltR = "AltR"
    AltS = "AltS"
    AltT = "AltT"
    AltU = "AltU"
    AltV = "AltV"
    AltW = "AltW"
    AltX = "AltX"
    AltY = "AltY"
    AltZ = "AltZ"

    AltShiftA = (3001, "AltShiftA")
    AltShiftB = "AltShiftB"
    AltShiftC = "AltShiftC"
    AltShiftD = "AltShiftD"
    AltShiftE = "AltShiftE"
    AltShiftF = "AltShiftF"
    AltShiftG = "AltShiftG"
    AltShiftH = "AltShiftH"
    AltShiftI = "AltShiftI"
    AltShiftJ = "AltShiftJ"
    AltShiftK = "AltShiftK"
    AltShiftL = "AltShiftL"
    AltShiftM = "AltShiftM"
    AltShiftN = "AltShiftN"
    AltShiftO = "AltShiftO"
    AltShiftP = "AltShiftP"
    AltShiftQ = "AltShiftQ"
    AltShiftR = "AltShiftR"
    AltShiftS = "AltShiftS"
    AltShiftT = "AltShiftT"
    AltShiftU = "AltShiftU"
    AltShiftV = "AltShiftV"
    AltShiftW = "AltShiftW"
    AltShiftX = "AltShiftX"
    AltShiftY = "AltShiftY"
    AltShiftZ = "AltShiftZ"


type
  UnknownKeyCodeHandler= proc(keyCode: int)
  UnknownEscapeSequenceHandler= proc(escSeq: string)

  
var
  handleUnknownKeyCode: UnknownKeyCodeHandler = nil
  handleUnknownEscapeSequence: UnknownEscapeSequenceHandler = nil


proc onUnknownKeyCode*(handler: UnknownKeyCodeHandler) = 
  handleUnknownKeyCode = handler


proc onUnknownEscapeSequence*(handler: UnknownEscapeSequenceHandler) = 
  handleUnknownEscapeSequence = handler


proc tryToKey(keyCode: int): Option[Key] =
  try:
    {.push warning[HoleEnumConv]: off.}
    result = some(Key(keyCode))
    {.pop.}
  except RangeDefect:
    if not handleUnknownKeyCode.isNil:
      handleUnknownKeyCode(keyCode)

    result = none(Key)


type 
  KeyEscapeSequenceTable = Table[Key, seq[string]]


var defaultKeyEscSeqTable*: KeyEscapeSequenceTable = {
  Key.Up: @["\e[A"],
  Key.Down: @["\e[B"],
  Key.Right: @["\e[C"],
  Key.Left: @["\e[D"],
  Key.Home: @["\e[1~"],
  Key.Insert: @["\e[2~"],
  Key.Delete: @["\e[3~"],
  Key.End: @["\e[4~"],
  Key.PageUp: @["\e[5~"],
  Key.PageDown: @["\e[6~"],
  Key.F1: @["\eOP"],
  Key.F2: @["\eOQ"],
  Key.F3: @["\eOR"],
  Key.F4: @["\eOS"],
  Key.F5: @["\e[15~"],
  Key.F6: @["\e[17~"],
  Key.F7: @["\e[18~"],
  Key.F8: @["\e[19~"],
  Key.F9: @["\e[20~"],
  Key.F10: @["\e[21~"],
  Key.F11: @["\e[23~"],
  Key.F12: @["\e[24~"],
}.toTable


proc getPressedKeys*(maxBufLen: int = 100, escSeqTable: KeyEscapeSequenceTable = defaultKeyEscSeqTable): seq[Key] = 

  let buffer = readPendingInput(maxBufLen)

  for escSeq in buffer:
    var k: Option[Key] = none(Key)

    case escSeq.len:
    of 1:
      k = tryToKey(int(escSeq[0]))
      doAssert k.isSome, "Fatal: Failed to convert known escape sequence to key"
      result.add(k.get)
    of 2:
      if escSeq[0] == '\e':
        if escSeq[1] in 'a' .. 'z':
          let keyCode = ord(escSeq[1]) - ord('a') + ord(Key.AltA)

          k = tryToKey(keyCode)
          doAssert k.isSome, "Fatal: Failed to convert known escape sequence to key"
          result.add(k.get)
        elif escSeq[1] in 'A' .. 'Z':
          let keyCode = ord(escSeq[1]) - ord('A') + ord(Key.AltShiftA)
          k = tryToKey(keyCode)
          doAssert k.isSome, "Fatal: Failed to convert known escape sequence to key"
          result.add(k.get)
      
    else:
      for key, value in escSeqTable:
        if escSeq in value:
          k = some(key)
          result.add(key)
          break

    if escSeq.len > 0 and k.isNone and not handleUnknownEscapeSequence.isNil:
      handleUnknownEscapeSequence(escSeq)


when isMainModule:
  proc getPressedKeysDemo() = 
    while true:
      let keys = getPressedKeys()
      if keys.len > 0:
        stdout.write(keys, "\r\n")
        if Key.Q in keys:
          break

    
  echo "Press key or mod+key combo for demo. Press q to quit."
  withRawMode:
    getPressedKeysDemo()
        
