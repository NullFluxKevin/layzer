import posix
import sets

export sets


type
  FileDescriptorSet* = HashSet[cint]
  Milliseconds* = Natural


proc toTimeval(duration: Milliseconds): Timeval =
  result.tv_sec = Time(duration div 1000)
  result.tv_usec = 1000 * (duration mod 1000)
  

proc makeSelectArgs*(fdSet: FileDescriptorSet): tuple[fds: TFdSet, maxFd: cint] =
  FD_ZERO(result.fds)  # initialize

  result.maxFd = -1

  for fd in fdSet:
    FD_SET(fd, result.fds) # add to the file descriptor set
    if fd > result.maxFd:
      result.maxFd = fd


proc getReadyToReadFds*(timeout: Milliseconds, readFds: FileDescriptorSet): FileDescriptorSet = 
  let tv = toTimeval(timeout)
  var (fds, maxFd) = makeSelectArgs(readFds)
  let selectFlag = select(maxFd + 1, addr fds, nil, nil, addr tv)
  doAssert selectFlag >= 0, "Fatal: An irrecoverable error occurred when calling select for checking file descriptors for reading."
  for fd in readFds:
    if FD_ISSET(fd, fds) != 0:
      result.incl(fd)


proc getReadyToWriteFds*(timeout: Milliseconds, writeFds: FileDescriptorSet): FileDescriptorSet = 
  let tv = toTimeval(timeout)
  var (fds, maxFd) = makeSelectArgs(writeFds)
  let selectFlag = select(maxFd + 1, nil, addr fds, nil, addr tv)
  doAssert selectFlag >= 0, "Fatal: An irrecoverable error occurred when calling select for checking file descriptors for writing."
  for fd in writeFds:
    if FD_ISSET(fd, fds) != 0:
      result.incl(fd)


when isMainModule:

  block test_makeSelectArgs:
    var fdSet = FileDescriptorSet()
    fdSet.incl(0)
    fdSet.incl(100)

    let (_, maxFd) = makeSelectArgs(fdSet)
    
    doAssert maxFd == 100

  block test_getReadyToReadFds:
    # create a pipe for testing
    var pipeFds: array[2, cint]    
    discard pipe(pipeFds)

    let
      readFd = pipeFds[0]
      writeFd = pipeFds[1]

    discard write(writeFd, "x".cstring, 1)

    var fdSet = FileDescriptorSet()
    fdSet.incl(readFd)

    let ready = getReadyToReadFds(500, fdSet)

    doAssert ready.contains(readFd)

    # clean up
    var dummy: char
    discard read(readFd, addr dummy, 1)
    discard close(readFd)
    discard close(writeFd)

  echo "All tests passed."

