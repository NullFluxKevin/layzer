# Great article about terminal raw mode:
# https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
import posix
import termios
import options

import selectWrapper


var
  isRawModeEnabled = false
  origAttr: Termios

type
  KeySequence* = string


const stdinFDSet = block:
  var fdSet = FileDescriptorSet()
  fdSet.incl(STDIN_FILENO)
  fdSet


proc isStdinReady*(timeout: Milliseconds): bool =

  doAssert isRawModeEnabled, "Error: Please enable raw terminal mode first using the enableRawMode proc or the withRawMode template."

  let readyFds = getReadyToReadFds(timeout, stdinFDSet)
  readyFds.contains(STDIN_FILENO)
    

proc getTermCtrlAttr(): Termios = 
  let ret = tcGetAttr(STDIN_FILENO, addr result)
  doAssert ret == 0, "Fatal: Failed to get terminal attributes"


proc setTermCtrlAttr(term: Termios) = 
  let ret = tcSetAttr(STDIN_FILENO, TCSAFLUSH, addr term)
  doAssert ret == 0, "Fatal: Failed to set terminal attributes"




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


proc setReadTimeout(term: var Termios) = 
  # Minimum number of bytes required to be read before return
  term.c_cc[VMIN] = 0.char
  # timeout (Unit: multiple of 100 ms, so VTIME=2 means 200ms)
  term.c_cc[VTIME] = 0.char


proc enableRawMode*() =
  if not isRawModeEnabled:
    origAttr = getTermCtrlAttr()

    # Termios is a value type, this is safe, raw is a copy of origAttr
    var raw = origAttr

    raw.disableInputEcho()
    raw.disableInputLineBuffer()
    raw.disableSignals()
    raw.disableOutputProcessing()
    raw.disableMiscFlags()

    raw.setReadTimeout()

    setTermCtrlAttr(raw)

    isRawModeEnabled = true


proc disableRawMode*() = 
  if isRawModeEnabled:
    setTermCtrlAttr(origAttr)
    isRawModeEnabled = false


template withRawMode*(body: untyped) = 
  try:
    enableRawMode()
    body
  finally:
    disableRawMode()


proc tryReadByte*(timeout: Milliseconds): Option[char] =
  result = none(char)

  if isStdinReady(timeout):
    var input: char
    let numBytesRead = read(STDIN_FILENO, addr input, 1)

    if numBytesRead == 1:
      result = some(input)

    elif numBytesRead == -1:
      doAssert errno == EAGAIN, "Fatal: Failed to read from stdin"
      result = none(char)


proc tryReadKeySequence*(timeout, escSeqTimeout: Milliseconds): Option[KeySequence] = 
  # escSeqTimeout is the wait time within which bytes collected will be considered part of the escape sequence. It should be small like 10ms, 50ms.
  result = none(KeySequence)

  let ret = tryReadByte(timeout)
  if ret.isSome:
    let ch = ret.get
    if ch == '\e':
      var escapeSequence = ""
      escapeSequence.add(ch)

      var r = tryReadByte(escSeqTimeout)
      while r.isSome:
        escapeSequence.add(r.get)
        r = tryReadByte(escSeqTimeout)
      result = some(escapeSequence)

    else:
      result = some($ret.get)


when isMainModule:
   # Utility proc that shows the bytes of a key for quick reference.
  proc showRawInputBytes() = 
    echo "Press a key to see it's sequence. Press q to quit"
    withRawMode:
      while true:
          let op = tryReadKeySequence(100, 10)
          if op.isSome:
            let keySeq = op.get
            stdout.write(repr(keySeq), "\r\n")
            if keySeq == "q":
              break

  showRawInputBytes()

      
  
