import os
import heapqueue
import times
import tables
import sets


type
  TimerID = Natural

  Timer = ref object
    id: TimerID
    isOneShot: bool
    interval: Duration
    due: Time


  TimerRegistry = Table[TimerID, proc()]
  TimerEventQueue = Channel[TimerID]
  TimerHandler = proc()
  TimerQueue = HeapQueue[Timer]

  TimerLoopCommandKind = enum
    tlckCancel, tlckAddTimer, tlckShutdown

  TimerLoopCommand = object
    case kind: TimerLoopCommandKind
    of tlckCancel:
      id: TimerID
    of tlckAddTimer:
      timer: Timer
    of tlckShutdown:
      discard

  CommandChannel = Channel[TimerLoopCommand]
  Millisecond = Natural


var
  timerEventQueue = TimerEventQueue()
  idCounter = 0
  cmdCh = CommandChannel()

timerEventQueue.open
cmdCh.open

const
  minIntervalAllowed = initDuration(milliseconds=1)


proc `<`(a, b: Timer): bool = a.due < b.due


iterator pollTimerIDs(): TimerID = 
  while true:
    let recv = timerEventQueue.tryRecv()
    if not recv.dataAvailable:
      break

    yield recv.msg


proc initTimer(interval: Duration, isOneShot: bool): Timer =
  let timerID = idCounter
  idCounter += 1
  Timer(id: timerID, isOneShot: isOneShot, interval: interval)


proc initTimer(interval: Millisecond, isOneShot: bool): Timer =
  let timerID = idCounter
  idCounter += 1
  Timer(id: timerID, isOneShot: isOneShot, interval: initDuration(milliseconds= interval))
  
  # initTimer(initDuration(milliseconds=interval), isOneShot)

proc registerTimer(registry: var TimerRegistry, timer: Timer, handler: TimerHandler) =
  registry[timer.id] = handler
  

proc cancelTimer(id: TimerID) = 
  cmdCh.send(TimerLoopCommand(kind: tlckCancel, id: id))

proc addTimer(timer: Timer) = 
  cmdCh.send(TimerLoopCommand(kind: tlckAddTimer, timer: timer))


proc shutdown() = 
  #[
    shutdown() gracefully terminates the timer system after the next due timer fires.
    Any commands in the queue (e.g. cancel, add) are still processed.
    No further timer events are scheduled.
    Thread joins are expected to happen after shutdown to ensure full cleanup.
  ]#
  cmdCh.send(TimerLoopCommand(kind: tlckShutdown))


proc add(timerQueue: var TimerQueue, newTimer: Timer) =
  var timer = newTimer
  doAssert minIntervalAllowed <= timer.interval, "Fatal: Intervals smaller than 1ms are not allowed."
  timer.due = getTime() + timer.interval
  timerQueue.push(timer)


proc startTimers(timers: seq[Timer]) {.thread.} = 

  var
    timerQueue = initHeapQueue[Timer]()
    pendingCancellations = HashSet[TimerID]()

  for timer in timers:
    timerQueue.add(timer)


  while true:
    let nextTimer = timerQueue.pop()

    if pendingCancellations.contains(nextTimer.id):
      pendingCancellations.excl(nextTimer.id)
      continue

    let timeTilActivation = nextTimer.due - getTime()
  
    doAssert DurationZero < timeTilActivation, "Fatal: Timer due time is in the past. This may indicate host time drift or a bug in timer setup." &
    "\nTimer ID: " & $nextTimer.id & 
    "\nDue: " & $nextTimer.due & 
    "\nNow: " & $getTime() & 
    "\nInterval: " & $nextTimer.interval

      
    let milsecs = timeTilActivation.inMilliseconds
    sleep(milsecs)

    var shutdown = false
    while true:
      let recv = cmdCh.tryRecv
      if not recv.dataAvailable:
        break

      let cmd = recv.msg
      case cmd.kind:
      of tlckCancel:
        pendingCancellations.incl(cmd.id)
      of tlckAddTimer:
        let newTimer = cmd.timer
        timerQueue.add(newTimer)
      of tlckShutdown:
        shutdown = true
       

    timerEventQueue.send(nextTimer.id)

    if not nextTimer.isOneShot:
      nextTimer.due = getTime() + nextTimer.interval
      timerQueue.push(nextTimer)

    if shutdown:
      break
   

when isMainModule:

  proc tick1Handler() =
    echo "tick 1"

  proc tick2Handler() =
    echo "tick 2"

  proc toBeCancelledTimerHandler() =
    doAssert false, "Fatal: The timer is supposed to be cancelled and never be triggered"

  proc runtimeOneShotHandler() =
    echo "One-shot timer added at runtime triggered"

  proc runtimeHandler() = 
    echo "Recurring timer added at runtime triggered"
  
  var timerRegistry = TimerRegistry()

  let tick1 = initTimer(10, false)
  let tick2 = initTimer(20, false)
  let toBeCancelledTimer = initTimer(15, false)

  timerRegistry.registerTimer(tick1, tick1Handler)
  timerRegistry.registerTimer(tick2, tick2Handler)
  timerRegistry.registerTimer(toBeCancelledTimer, toBeCancelledTimerHandler)
  var timers: seq[Timer] = @[tick1, tick2, toBeCancelledTimer]

  var timerThread: Thread[seq[Timer]]
  createThread(timerThread, startTimers, timers)

  # The timer thread must be started before sending control commands.
  # Commands (like cancellation) are only processed once the timer loop is running.
  # 
  # IMPORTANT:
  # The effect of sending a cancellation command before the loop starts is *not* guaranteed, unless the target timer's due time is far enough in the future to allow the cancellation to be processed *before* the timer is activated.
  # 
  # This behavior is by design: control commands are part of the running timer system, and cannot take effect before it begins.
  cancelTimer(toBeCancelledTimer.id)

  let
    runtimeOneShotTimer = initTimer(50, true)
    runtimeTimer = initTimer(30, false)

  # future API clean up: accept timer and access the .id in proc body
  timerRegistry.registerTimer(runtimeOneShotTimer, runtimeOneShotHandler)
  timerRegistry.registerTimer(runtimeTimer, runtimeHandler)

  addTimer(runtimeOneShotTimer)
  addTimer(runtimeTimer)

  var timerCounter = 0
  while true:
    for timerID in pollTimerIDs():
      timerRegistry[timerID]()
      inc timerCounter

    # pretend to do useful work
    sleep(5)

    if timerCounter > 100:
      shutdown()
      break

  # these are optional
  # timerEventQueue.close
  # cmdCh.close

  joinThread(timerThread)

