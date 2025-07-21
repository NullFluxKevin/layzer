import os
import heapqueue
import times
import tables


var idCounter = 0
 
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


var
  timerEventQueue = TimerEventQueue()


proc `<`(a, b: Timer): bool = a.due < b.due


iterator pollTimerID(): TimerID = 
  while true:
    let recv = timerEventQueue.tryRecv()
    if not recv.dataAvailable:
      break

    yield recv.msg


proc initTimer(interval: Duration, isOneShot: bool): Timer =
  let timerID = idCounter
  idCounter += 1
  Timer(id: timerID, isOneShot: isOneShot, interval: interval)


proc registerTimer(registry: var TimerRegistry, timerID: TimerID, handler: TimerHandler) =
  registry[timerID] = handler
  

proc startTimers(timers: seq[Timer]) {.thread.} = 

  var timerQueue = initHeapQueue[Timer]()

  for timer in timers:

    timer.due = getTime() + timer.interval
    timerQueue.push(timer)



  while true:
    let
      nextTimer = timerQueue.pop()
      timeTilActivation = nextTimer.due - getTime()

    doAssert DurationZero <= timeTilActivation, "Fatal: Timer due time is in the past. This may indicate host time drift or a bug in timer setup. " &
    "Timer ID: " & $nextTimer.id & 
    ", Due: " & $nextTimer.due & 
    ", Now: " & $getTime() & 
    ", Interval: " & $nextTimer.interval

      

    let milsecs = timeTilActivation.inMilliseconds
    sleep(milsecs)

    # Has to be checked AFTER the thread wakes up to prevent from sending to closed channel by race condition
    let isTimerEventQueueClosed = timerEventQueue.peek == -1
    if isTimerEventQueueClosed:
      return

    timerEventQueue.send(nextTimer.id)

    if not nextTimer.isOneShot:
      nextTimer.due = getTime() + nextTimer.interval
      timerQueue.push(nextTimer)
   

when isMainModule:

  timerEventQueue.open

  proc tick1SecHandler() =
    echo "tick every 1 sec"

  proc tick2SecsHandler() =
    echo "tick every 2 secs"
    
  
  var timerRegistry = TimerRegistry()

  let tick1sec = initTimer(initDuration(seconds=1), false)
  let tick2secs = initTimer(initDuration(seconds=2), false)

  timerRegistry.registerTimer(tick1sec.id, tick1SecHandler)
  timerRegistry.registerTimer(tick2secs.id, tick2SecsHandler)
  var timers: seq[Timer] = @[tick1sec, tick2Secs]

  var timerThread: Thread[seq[Timer]]
  createThread(timerThread, startTimers, timers)

  var timerCounter = 0
  while true:
    for timerID in pollTimerID():
      timerRegistry[timerID]()
      inc timerCounter

    # pretend to do useful work
    sleep(500)

    if timerCounter > 10:
      break

  # This is how we signal the timer thread to stop the loop
  timerEventQueue.close

  joinThread(timerThread)
      

