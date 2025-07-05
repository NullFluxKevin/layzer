# Great article about terminal raw mode:
# https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
import posix
import termios
import options

type ReadTimeout* = distinct int

proc toReadTimeout*(timeoutMS: int): ReadTimeout = 
  doAssert timeoutMS >= 0 and timeoutMS mod 100 == 0, "Error: timeoutMS must be a positive multiple of 100 or 0"
  ReadTimeout(timeoutMS div 100)

proc getTermCtrlAttr(): Termios = 
  let ret = tcGetAttr(STDIN_FILENO, addr result)
  doAssert ret == 0, "Fatal: Failed to get terminal attributes"

proc setTermCtrlAttr(term: Termios) = 
  let ret = tcSetAttr(STDIN_FILENO, TCSAFLUSH, addr term)
  doAssert ret == 0, "Fatal: Failed to set terminal attributes"

let origAttr = getTermCtrlAttr()


proc disableControlFlag(flag: var Cflag, mask: Cflag) =
  flag = flag and not mask


# Don't print keypress on screen
proc disableInputEcho(term: var Termios) =
  disableControlFlag(term.c_lflag, ECHO)


# Send each keypress immediately without waiting for Enter to be pressed
proc disableInputLineBuffer(term: var Termios) = 
  disableControlFlag(term.c_lflag, ICANON)


proc disableSignals(term: var Termios) = 
  # Disable ctrl-c, ctrl-z (and ctrl-y on macOS)
  disableControlFlag(term.c_lflag, ISIG)

  # Disable ctrl-s, ctrl-q
  disableControlFlag(term.c_iflag, IXON)

  # Disable ctrl-v, and ctrl-o on macOS
  disableControlFlag(term.c_iflag, IEXTEN)

  # Disable ctrl-m
  disableControlFlag(term.c_iflag, ICRNL)


# Don't translate \n to \r\n
proc disableOutputProcessing(term: var Termios) = 
  disableControlFlag(term.c_oflag, OPOST)


proc disableMiscFlags(term: var Termios) = 
  disableControlFlag(term.c_iflag, BRKINT)
  disableControlFlag(term.c_iflag, INPCK)
  disableControlFlag(term.c_iflag, ISTRIP)
  disableControlFlag(term.c_cflag, CS8)


proc setReadTimeout(term: var Termios, readTimeout: ReadTimeout) = 
  # Minimum number of bytes required to be read before return
  term.c_cc[VMIN] = 0.char
  term.c_cc[VTIME] = readTimeout.char


proc enableRawMode*(readTimeout: ReadTimeout = 100.toReadTimeout) =
  var raw = getTermCtrlAttr()

  raw.disableInputEcho()
  raw.disableInputLineBuffer()
  raw.disableSignals()
  raw.disableOutputProcessing()
  raw.disableMiscFlags()

  raw.setReadTimeout(readTimeout)

  setTermCtrlAttr(raw)


proc disableRawMode*() = 
  setTermCtrlAttr(origAttr)


template withRawMode*(body: untyped) = 
  try:
    enableRawMode()
    body
  finally:
    disableRawMode()

  
proc tryReadByte*(): Option[char] = 
  var input: char
  let numBytesRead = read(STDIN_FILENO, addr input, 1)

  if numBytesRead == 1:
    result = some(input)

  elif numBytesRead == -1:
    doAssert errno == EAGAIN, "Fatal: Failed to read from stdin"
    result = none(char)
  

when isMainModule:
  withRawMode:
    while true:
       let input = tryReadByte()

       if input.isSome:

         let c = input.get
         if c == 'q':
           break
         else:
           stdout.write(c, "\r\n")

       else: 
         stdout.write("No input. Press q to quit.", "\r\n")
      
  
