# Great article about terminal raw mode:
# https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
import posix
import termios
import options

import selectWrapper


const
  defaultReadTimeout = 100
  defaultEscSequenceReadTimeout = 10
  defaultMaxInputBufLen = 100


type
  ReadTimeout* = distinct int
  InputBuffer* = seq[string]


const stdinFDSet = block:
  var fdSet = FileDescriptorSet()
  fdSet.incl(STDIN_FILENO)
  fdSet


proc isStdinReady*(timeoutMS: int): bool =
  let readyFds = getReadyToReadFds(timeoutMS, stdinFDSet)
  readyFds.contains(STDIN_FILENO)
    

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


proc setReadTimeout(term: var Termios) = 
  # Minimum number of bytes required to be read before return
  term.c_cc[VMIN] = 0.char
  # timeout (Unit: multiple of 100 ms, so VTIME=2 means 200ms)
  term.c_cc[VTIME] = 0.char


proc enableRawMode*() =
  var raw = getTermCtrlAttr()

  raw.disableInputEcho()
  raw.disableInputLineBuffer()
  raw.disableSignals()
  raw.disableOutputProcessing()
  raw.disableMiscFlags()

  raw.setReadTimeout()

  setTermCtrlAttr(raw)


proc disableRawMode*() = 
  setTermCtrlAttr(origAttr)


template withRawMode*(body: untyped) = 
  try:
    enableRawMode()
    body
  finally:
    disableRawMode()


proc tryReadByte*(timeoutMS: int = defaultReadTimeout): Option[char] =
  result = none(char)

  if isStdinReady(timeoutMS):
    var input: char
    let numBytesRead = read(STDIN_FILENO, addr input, 1)

    if numBytesRead == 1:
      result = some(input)

    elif numBytesRead == -1:
      doAssert errno == EAGAIN, "Fatal: Failed to read from stdin"
      result = none(char)
    

proc readPendingInput*(maxBufLen: Positive = defaultMaxInputBufLen): InputBuffer = 
  while result.len < maxBufLen:
    let ret = tryReadByte()
    if ret.isSome:
      let ch = ret.get
      if ch == '\e':
        var escapeSequence = ""
        escapeSequence.add(ch)

        var r = tryReadByte(defaultEscSequenceReadTimeout)
        while r.isSome:
          escapeSequence.add(r.get)
          r = tryReadByte(defaultEscSequenceReadTimeout)

        result.add(escapeSequence)

      else:
        result.add($ret.get)

    else:
      break


when isMainModule:
   # Utility proc that shows the bytes of a key for quick reference.
  proc showRawInputBytes() = 
    echo "Press a key to see it's bytes. Press q to quit"
    withRawMode:
      while true:
        let buffer = readPendingInput()
        if buffer.len != 0:
          stdout.write(repr(buffer), "\r\n")
          if "q" in buffer:
            break

  showRawInputBytes()

      
  
