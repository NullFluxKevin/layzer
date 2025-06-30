import os
import terminal
import posix

type
  EventHandler[T] = proc(ctx: T)
  Event[T] = object
    handlers: seq[EventHandler[T]]


proc initEvent[T](): Event[T] = 
  Event[T]()

proc subscribe[T](e: var Event[T], handler: EventHandler[T]) =
  e.handlers.add(handler)

proc invoke[T](e: Event[T], ctx: T) =
  for handler in e.handlers:
    handler(ctx)


when isMainModule:
  block test_basic_event:
    type
      GreetEventContext = object
        name: string

    proc hey(ctx: GreetEventContext) =
      echo "Hey, ", ctx.name

    proc bye(_: GreetEventContext) =
      echo "Bye"

    var greet = initEvent[GreetEventContext]()
    greet.subscribe(hey)
    greet.subscribe(bye)

    greet.invoke(GreetEventContext(name: "John"))

  block test_TUI_resize:

    const SIGWINCH = 28

    type
      ResizeEventContext = object
        newWidth, newHeight: int

    proc onResize(ctx: ResizeEventContext) = 
      echo "New terminal window size: ", ctx.newWidth, ", ", ctx.newHeight

    var
      hasResized = false
      resize = initEvent[ResizeEventContext]()
    resize.subscribe(onResize)

    echo "You have to change the size of the ternimal for testing"
    echo "Stop manually with ctrl-c when you are done testing"

    signal(SIGWINCH, proc(sigwinch: cint) {.noconv.} = hasResized = true)

    while true:
      if hasResized:
        var
          width = terminalWidth()
          height = terminalHeight()
        resize.invoke(ResizeEventContext(newWidth: width, newHeight: height))
        hasResized = false
