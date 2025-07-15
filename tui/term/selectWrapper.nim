import posix
import sets

export sets

type FileDescriptorSet* = HashSet[cint]


proc toTimeval*(ms: int): Timeval =
  result.tv_sec = Time(ms div 1000)
  result.tv_usec = 1000 * (ms mod 1000)
  

proc makeSelectArgs*(fdSet: FileDescriptorSet): tuple[fds: TFdSet, maxFd: cint] =
  FD_ZERO(result.fds)  # initialize

  result.maxFd = -1

  for fd in fdSet:
    FD_SET(fd, result.fds) # add to the file descriptor set
    if fd > result.maxFd:
      result.maxFd = fd


proc getReadyToReadFds*(timeoutMS: int, readFds: FileDescriptorSet): FileDescriptorSet = 
  let tv = toTimeval(timeoutMS)
  var (fds, maxFd) = makeSelectArgs(readFds)
  discard select(maxFd + 1, addr fds, nil, nil, addr tv)
  for fd in readFds:
    if FD_ISSET(fd, fds) != 0:
      result.incl(fd)


proc getReadyToWriteFds*(timeoutMS: int, writeFds: FileDescriptorSet): FileDescriptorSet = 
  let tv = toTimeval(timeoutMS)
  var (fds, maxFd) = makeSelectArgs(writeFds)
  discard select(maxFd + 1, nil, addr fds, nil, addr tv)
  for fd in writeFds:
    if FD_ISSET(fd, fds) != 0:
      result.incl(fd)


when isMainModule:

  block test_makeSelectArgs:
    var fdSet = FileDescriptorSet()
    fdSet.incl(0)
    fdSet.incl(100)

    let (fds, maxFd) = makeSelectArgs(fdSet)
    
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
    discard read(readFd, cast[pointer](alloc(1)), 1)
    discard close(readFd)
    discard close(writeFd)

