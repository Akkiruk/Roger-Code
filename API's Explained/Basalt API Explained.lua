Perfect, I’ll gather everything available about the latest version of the Basalt API for ComputerCraft. This will include a full breakdown of all modules, functions, classes, properties, events, usage patterns, error handling, and best practices. I’ll also include code examples and organize it into a structured, standalone resource suitable for training or development.

I’ll get started now and update you as soon as it’s ready.

# Basalt UI Framework for ComputerCraft: Comprehensive Guide

## Introduction and Purpose of Basalt

**Basalt** is a graphical UI framework for the ComputerCraft: Tweaked mod in Minecraft. It provides a high-level API to create windows, buttons, text fields, menus, and other GUI components on ComputerCraft computers or monitors ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=What%20is%20Basalt%3F)). By handling low-level details like event management and screen drawing for you, Basalt makes it easier to build interfaces “easily and efficiently” than manipulating the terminal directly ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Basalt%20is%20a%20UI%20framework,features%20like%20animations%20and%20themes)). Its features include pre-built UI elements, an event/callback system, state management, themes, and animations ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Basalt%20is%20a%20UI%20framework,features%20like%20animations%20and%20themes)) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=,Layout%20organization)) – enabling anything from simple input dialogs to full graphical operating systems ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=Basalt%20is%20very%20advanced%20UI,a%20very%20advanced%20operating%20system)). Basalt is designed for CC:Tweaked on modern Minecraft (older 1.7.10 ComputerCraft is *not* supported) ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=There%20are%20some%20objects%20i,there%20are%20some%20missing%20information)).

**Installation:** To install Basalt on a ComputerCraft computer, use the official installer. In the shell, run: 

```lua
wget run https://raw.githubusercontent.com/Pyroxenium/Basalt2/main/install.lua
``` 

This opens an installer UI where you can choose the latest release or dev version ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=lua)). (You may also use `-r` or `-d` flags for direct release/dev installation as documented.) After installation, Basalt’s files are placed on the computer. In your Lua program, load Basalt with: 

```lua
local basalt = require("basalt")  -- load the Basalt API library ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=Before%20you%20can%20access%20Basalt%2C,on%20top%20of%20your%20file))
``` 

This returns the Basalt API table which we’ll use throughout. Basalt runs on both in-game computer screens and attached monitors – you can even direct a Basalt UI to a monitor peripheral using `setMonitor()` (added in v1.7) to display the interface externally ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=The%20old%20version%20of%20basalt,side)).

## Getting Started: Frames and the Basalt Runtime

**Frames:** In Basalt, every UI lives inside a **Frame**. A Frame is a container window (akin to a screen or panel) that holds UI elements. The top-level frame (a **BaseFrame**) is typically created for you and tied to a specific terminal (by default, the computer’s own terminal). You can obtain this main frame via `basalt.getMainFrame()` ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=,frame)). For example:

```lua
local basalt = require("basalt")
local main = basalt.getMainFrame()         -- get the main UI frame (attached to term.current())
```

You can also create additional frames with `basalt.createFrame()`, which returns a new BaseFrame object (for multi-window UIs or to attach to monitors) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). If using multiple frames, you can switch which one is active (receiving events) via `basalt.setActiveFrame(frame)` ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). To target a monitor, Basalt v1.7 introduced `BaseFrame:setMonitor(side)` to bind a frame to a monitor on a given side, and `BaseFrame:setMirror(side)` to mirror the main screen to a monitor ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=The%20old%20version%20of%20basalt,side)).

**Starting the UI Loop:** Basalt applications run an internal event loop that processes input and updates the UI. To start it, call `basalt.run()` when your UI setup is done ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). This call will enter Basalt’s loop and continuously handle events (mouse clicks, keypresses, etc.), repainting the UI as needed. **Without calling `basalt.run()`, the UI will not appear or respond** ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F)). Place it at the end of your program (it will block until the UI exits or `basalt.stop()` is called). For example:

```lua
-- (After building UI elements…)
basalt.run()  -- start Basalt runtime to display the UI ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F))
```

Basalt will automatically render the interface and only re-render when something changes, which makes it efficient even if many events (e.g. timers) are firing ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=,elements%20that%20actually%20use%20them)). If needed, you can terminate the loop by calling `basalt.stop()` to break out of `basalt.run()` (for instance, on a certain event). Basalt also provides `basalt.update(event...)` to manually pump a single event through the UI loop (advanced use – typically not needed when using `run()` which handles events continuously) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). 

**Basic Example:** The snippet below demonstrates a minimal Basalt program that creates a button on the screen:

```lua
local basalt = require("basalt")
local main = basalt.getMainFrame()            -- root frame (full screen by default)

main:addButton()                              -- create a Button on the frame
    :setText("Click me!")                     -- set button label text
    :setPosition(4, 4)                        -- place it at column 4, row 4
    :onClick(function() 
        print("Button was clicked!") 
    end)                                      -- attach an onClick event handler

basalt.run()  -- start the UI loop
```

When run, this will open the main frame, draw a button labeled “Click me!” at the given position, and print a message to the console whenever the button is clicked ([Getting Started with Basalt | Basalt](https://basalt.madefor.cc/guides/getting-started.html#:~:text=,Do%20something%20when%20clicked%20end)) ([Getting Started with Basalt | Basalt](https://basalt.madefor.cc/guides/getting-started.html#:~:text=%3AonClick%28function%28%29%20,clicked%20end)). (In a real program you might update the UI or state instead of printing to console.)

## Basalt API Components Overview

Basalt’s API can be thought of in a few parts: the **Basalt module** functions (for top-level control and utilities), the **UI element classes** (Frames, Buttons, etc.), and various **systems/plugins** (property system, state, animations, themes, etc.). Below is a breakdown of key components, including their functions, properties, and events.

### Basalt Module (Top-Level API)

When you `require("basalt")`, you get a table with global control functions and settings. Important ones include:

- **`basalt.getMainFrame()`** – Returns the primary `BaseFrame` (creating it if needed) for the current terminal ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=,frame)). This main frame typically covers the whole screen or monitor by default.
- **`basalt.createFrame()`** – Creates a new `BaseFrame` (a new top-level window). You might use this for additional monitors or separate UI contexts ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)).
- **`basalt.run(isActive?)`** – Starts the Basalt runtime loop ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). (The optional boolean can control if the frame starts active; usually you omit it or pass `true`.)
- **`basalt.stop()`** – Stops the Basalt runtime, causing `basalt.run()` to return ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)).
- **`basalt.update(event...)`** – Processes a single event and updates UI once ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). Useful if you want manual control of the event loop or integrate Basalt into another event loop.
- **`basalt.schedule(func)`** – Schedules a function to run in a parallel coroutine ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). This allows running background tasks without freezing the UI. It returns a thread handle. (Similar to ComputerCraft’s `parallel` API but integrated into Basalt’s update cycle.)
- **`basalt.removeSchedule(thread)`** – Removes a previously scheduled coroutine (cancels it) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=Parameters)).
- **`basalt.create(type, properties?)`** – Low-level factory to create a new UI element by type name (e.g. `"Button"` or `"Label"`). You usually won’t call this directly; instead use frame methods like `frame:addButton()`, but it’s available ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=lua)).
- **`basalt.setActiveFrame(frame)`** – If you have multiple frames, this sets which one is currently active (accepting user input) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). Only one frame per terminal is active at a time.
- **`basalt.getActiveFrame(term?)`** – Retrieves the active frame for a given terminal (defaults to the current term) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)).
- **`basalt.getFocus()`** – Returns the frame currently focused (if any) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). (Focus in Basalt refers to which frame has input focus in multi-frame setups.)
- **`basalt.getElementManager()`**, **`basalt.getErrorManager()`**, **`basalt.getAPI(name)`** – Access internal managers and plugin APIs ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). For example, `basalt.getAPI("ThemeAPI")` returns the theme system’s API. These are advanced usage; typically you’ll use higher-level methods.

**Module Fields:** The Basalt module also has some fields you can read/modify:
- **`basalt.traceback`** – Boolean flag controlling whether error messages include a stack traceback ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=Field%20Type%20Description%20traceback%20,path%20to%20the%20Basalt%20library)). By default it may be `true` (meaning if your UI code errors, Basalt will print a Lua traceback for debugging).
- **`basalt.isRunning`** – Boolean indicating if the Basalt event loop is currently running ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=_schedule%20%60function,path%20to%20the%20Basalt%20library)).
- **`basalt.path`** – The path where Basalt is installed (useful if you need to load additional Basalt files manually) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=_plugins%20,path%20to%20the%20Basalt%20library)).
- **`basalt.LOGGER`** – The Basalt logger instance (see **Error Handling & Debugging** below) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=_events%20,path%20to%20the%20Basalt%20library)).

### UI Elements and Their Properties

Basalt comes with a rich set of UI element classes (also called **objects**) for building interfaces. All elements share a common design: they have **properties** (which define their state/appearance), support **methods** (including chainable setters), and may fire **events** for user interactions. Internally, elements inherit from a base class hierarchy (`BaseElement` -> `VisualElement` -> possibly `Container` -> specific element), but as a user you mostly interact with them via their API.

**Adding Elements:** You typically create UI elements as children of a frame or container. For example, `frame:addButton()` will create a Button inside that frame. Each frame/container provides `addX()` methods for each element type. You can chain setter calls after creating an element (because `addX()` returns the new element). Alternatively, you can pass a table of initial properties to `addX({...})` to set multiple properties at once ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=,)). Both approaches are shown below and are equivalent:

```lua
-- Using chained setters:
local btn1 = mainFrame:addButton()
            :setText("OK")
            :setPosition(2, 2)
            :setSize(6, 1)

-- Using an init table:
local btn2 = mainFrame:addButton({
    text = "OK",
    x = 2, y = 2,
    width = 6, height = 1
})
```

Under the hood, Basalt’s **Property System** will apply those values to the new element ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=,)) ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=,Click%20me)). You can also directly set properties on an element after creation (e.g. `btn2.x = 5`) – this is convenient and will still trigger any observers or validation associated with that property ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=lua)). The property system supports three ways to get/set values: (1) chainable methods like `setX()` (most thorough validation) ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=lua)), (2) direct field access (`element.x = ...`) ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=lua)), or (3) generic calls `element.set("x", value)` / `element.get("x")` for dynamic property names ([Properties in Basalt | Basalt](https://basalt.madefor.cc/guides/properties.html#:~:text=lua)). The behavior is similar in all cases (with minor differences in overhead and validation).

**Common Properties:** Every visual element (anything drawn on screen) shares certain core properties inherited from the base classes:
- **Position and Size:** `x`, `y` (coordinates relative to parent, origin at top-left), and `width`, `height` (size in characters). These can also be set together via combined properties `position` (x,y) and `size` (width,height) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=Properties)) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=Combined%20Properties)). By default `x=y=1` and `width=height=1` for new elements.
- **Visual Appearance:** `background` and `foreground` (colors) control the element’s background and text color ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=width%20number%201%20The%20width,Whether%20to%20render%20the%20background)). There are also booleans `backgroundEnabled` (if false, the background is transparent) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=clicked%20boolean%20false%20Whether%20the,to%20ignore%20the%20parent%27s%20offset)) and `visible` (if false, the element is hidden entirely) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=%28Craftos,to%20ignore%20the%20parent%27s%20offset)).
- **Z-index:** `z` property controls layering; higher `z` means drawn on top of lower ones ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=Property%20Type%20Default%20Description%20x,the%20element%20is%20currently%20clicked)). By default all elements have z=1. You can bring an element to the front by calling `element:prioritize()` to give it the top z within its parent ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=VisualElement%3AisInBounds%20boolean%20Checks%20if%20point,top%20of%20its%20parent%27s%20children)).
- **Focus and Hover:** `focused` (bool) indicates if the element currently has keyboard focus ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=clicked%20boolean%20false%20Whether%20the,to%20ignore%20the%20parent%27s%20offset)). `hover` (bool) indicates if the mouse cursor is currently over the element (this works only in environments that support a mouse cursor, like CraftOS-PC) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=background%20color%20black%20The%20background,to%20ignore%20the%20parent%27s%20offset)).
- **Offsets (for containers):** Containers (scrollable frames, etc.) have `offsetX`, `offsetY` to scroll their content ([Container : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Container.html#:~:text=focusedChild%20table%20nil%20The%20focused,number%200%20Vertical%20content%20offset)). Combined as `offset` property.
- **Type/Identity:** Every element has `id` and `name` fields (often unused unless you assign them for lookup) and a `type` string (e.g. `"Button"`) identifying its class ([BaseElement : PropertySystem | Basalt](https://basalt.madefor.cc/references/elements/BaseElement.html#:~:text=Properties)).

These properties can all be manipulated via setters or directly. For example, `element:setPosition(10,5)` or `element.x = 10`. Position, size, and similar properties can also be **dynamic** – Basalt supports setting them with **expressions or functions** to respond to layout changes. For instance, you can set an element’s width as a formula relative to its parent: 

```lua
element:setSize("{parent.width - 10}", 5)  -- width stays 10 less than parent’s width ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Use%20dynamic%20positioning%20with%20strings%2C,or%20use%20functions))
``` 

This uses a string expression `{parent.width - 10}` which Basalt will evaluate reactively whenever the parent’s width changes (e.g. on a monitor resize). Similarly, you can provide a Lua function for a property to compute it on the fly ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Use%20dynamic%20positioning%20with%20strings%2C,or%20use%20functions)). This *reactive property* feature (introduced in newer versions) simplifies responsive UI design – Basalt will automatically update the UI when the expression’s dependencies change ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=Dynamic%20Values%20is%20a%20new,button1.y)).

**Element Events:** Interactive elements in Basalt can trigger events (callbacks) when the user interacts with them. You register event handlers using `element:onEventName(fn)`. For example, `button:onClick(fn)` registers a function to run when that button is clicked. The most common events, available on all **VisualElement**s, include:
- **`onClick(button, x, y)`** – Fired when a mouse button is pressed on the element ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=Event%20Parameters%20Description%20onClick%20,Fired%20when%20element%20receives%20focus)). Provides which mouse `button` (e.g. `"left"` or `"right"`) and the click coordinates relative to the element.
- **`onMouseUp(button, x, y)`** – When a pressed mouse button is released over the element ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onClick%20,Fired%20when%20element%20loses%20focus)).
- **`onRelease(button, x, y)`** – When the mouse was clicked and then moved off the element (mouse drag out) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onClick%20,Fired%20when%20element%20loses%20focus)).
- **`onDrag(button, x, y)`** – When the mouse is moved while clicking/dragging on the element ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onRelease%20,Fired%20on%20key%20press)).
- **`onScroll(direction, x, y)`** – Fired on mouse scroll wheel events over the element (direction is typically 1 or -1) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onRelease%20,Fired%20on%20key%20press)).
- **`onEnter` / `onLeave`** – Mouse entered or left the element’s area (CraftOS-PC only, since vanilla CC terminals have no cursor) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onScroll%20,Fired%20when%20element%20loses%20focus)).
- **`onFocus` / `onBlur`** – Element gained or lost keyboard focus ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onEnter%60,Fired%20when%20element%20loses%20focus)).
- **`onKey(key)`** / **`onKeyUp(key)`** – Key pressed/released while this element is focused ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onFocus%60,Fired%20on%20character%20input)). `key` is a numeric key code.
- **`onChar(char)`** – Character typed (for focused text inputs) ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=onBlur%60,Fired%20on%20character%20input)).

In addition, many elements define their own custom events (e.g. a List has an `onSelect` event when an item is chosen ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=Events)), or a Slider has `onChange` when its value moves ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Events))). We will note those per element below. **Registering an event:** Use the colon notation with the event name, e.g. `checkbox:onClick(function(btn,x,y) ... end)`. Internally, this uses Basalt’s `registerEventCallback`, but you rarely need to call that directly ([BaseElement : PropertySystem | Basalt](https://basalt.madefor.cc/references/elements/BaseElement.html#:~:text=Method%20Returns%20Description%20BaseElement.defineEvent,and%20calls%20all%20registered%20callbacks)) – the sugar `:onEvent` methods are provided for you.

Now, let’s survey all the key UI element types provided by Basalt in its latest version, along with their main properties and usage:

#### Container Elements (Frames & Containers)
- **BaseFrame:** The root container for a UI. It extends `Container` and represents an independent screen or window. A BaseFrame has no parent (it’s bound to a terminal or monitor) ([BaseFrame : Container | Basalt](https://basalt.madefor.cc/references/elements/BaseFrame.html#:~:text=BaseFrame%20%3A%20Container)). Key property: `term` – the Terminal object it draws to (e.g. `term.current()` by default) ([BaseFrame : Container | Basalt](https://basalt.madefor.cc/references/elements/BaseFrame.html#:~:text=Properties)). Usually obtained via `basalt.getMainFrame()` or `basalt.createFrame()`. BaseFrame also provides methods like `:showDebugLog()` / `:hideDebugLog()` to toggle Basalt’s debug console (see Debugging) ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=Method%20Returns%20Description%20BaseFrame.hideDebugLog,Toggles%20the%20debug%20log%20frame)). In multi-monitor setups, each BaseFrame can be tied to a different terminal.
- **Frame:** A generic container that can hold child elements (similar to a panel or sub-window). It extends `Container` as well, but unlike BaseFrame it has a parent (so it appears within another frame or container). Frames can be used to group UI elements or implement draggable windows. They have a `draggable` property (false by default) – if true, the user can click and drag the frame around within its parent ([Frame : Container | Basalt](https://basalt.madefor.cc/references/elements/Frame.html#:~:text=This%20is%20the%20frame%20class,grouping%20container%20for%20other%20elements)). This is useful for creating movable windows. 
- **Container:** The base class for any element that can hold children (both BaseFrame and Frame inherit from Container). It provides functionality for managing child elements (like `addChild`, `removeChild`, clearing children) ([Container : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Container.html#:~:text=Method%20Returns%20Description%20Container%3AaddChild%20Container,the%20children%20events%20of%20the)) ([Container : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Container.html#:~:text=Container%3AcallChildrenEvent%20boolean%20Calls%20a%20event,a%20child%20from%20the%20container)). Containers manage child layering and event dispatch to children automatically. Scrollable containers can use `offsetX/offsetY` properties to scroll content ([Container : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Container.html#:~:text=visibleChildrenEvents%20table,number%200%20Vertical%20content%20offset)).
- **Flexbox (new in v1.7):** A special container that automatically lays out its children either in a row or column, with flex-grow/shrink behavior (similar to CSS Flexbox). *This was introduced as a new object in Basalt v1.7* ([Release Basalt v1.7 · Pyroxenium/Basalt · GitHub](https://github.com/Pyroxenium/Basalt/releases/tag/v1.7#:~:text=,Reworked%20the%20XML%20System)) to simplify responsive layouts. You can specify orientation and the Flexbox will position child elements evenly or according to their configured flex properties. *(As of this writing, consult the Basalt documentation for exact usage of Flexbox; it inherits from Container and manages children’s `x`,`y` automatically.)*
- **Program:** A unique element that embeds another program’s execution within your UI. The Program element creates a sub-terminal and runs a given program/path inside it ([Program : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Program.html#:~:text=Program%20%3A%20VisualElement)). In other words, it’s like having a ComputerCraft **terminal window** inside your UI that can execute another Lua script. Key properties: `path` (the program path to run) and `running` (bool indicating if it’s active) ([Program : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Program.html#:~:text=Properties)). Use `programElement:execute("path/to/script")` to launch the program ([Program : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Program.html#:~:text=Program%3Aexecute)). This is useful for creating multi-tasking UIs or embedding utilities (for example, a shell or a live output panel) within a Basalt GUI.

#### Basic Controls (Input and Display Widgets)
- **Label:** A text label for displaying static or dynamic text. It auto-sizes to fit its content by default ([Label : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Label.html#:~:text=Properties)). Properties: `text` (the string to display; can also be a function for dynamic text) and `autoSize` (bool, default true, which makes the label’s width adjust to text length) ([Label : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Label.html#:~:text=Property%20Type%20Default%20Description%20text,based%20on%20the%20text%20content)). If `autoSize` is false, the label will word-wrap or truncate text to its set width. There’s a method `label:getWrappedText()` to retrieve how text is wrapped into lines ([Label : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Label.html#:~:text=Method%20Returns%20Description%20Label%3AgetWrappedTexttable%20Gets,wrapped%20lines%20of%20the%20Label)).
- **Button:** A clickable button with a text label. By default its `text` is `"Button"` ([Button : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Button.html#:~:text=Properties)), which you’ll typically override via `:setText()` or property. A button highlights on click and triggers `onClick` events when activated. Buttons can be used for any interactive action. (They don’t have many unique properties aside from `text` – styling of button press is handled internally.)
- **Checkbox:** A toggleable check box (on/off state). Its main property is `checked` (boolean) to indicate if it’s checked or not ([Checkbox : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Checkbox.html#:~:text=Properties)). It can also display text label(s): `text` (label when unchecked) and `checkedText` (label when checked) ([Checkbox : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Checkbox.html#:~:text=Property%20Type%20Default%20Description%20checked,to%20automatically%20size%20the%20checkbox)). By default it displays an `[X]` or `[ ]` along with any text. Toggling a checkbox fires the `onClick` event (you can check its new state via `checkbox:getValue()` or just query `checkbox.checked`).
- **Input (Text Field):** A single-line text input box that the user can type into ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=This%20is%20the%20input%20class,placeholder%20text%2C%20and%20input%20validation)). It supports a cursor, horizontal scrolling for long text, and built-in validation features. Key properties include: `text` (current content), `cursorPos` (current cursor index) ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=Properties)), `maxLength` (optional max characters) ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=cursorPos%20number%201%20The%20current,nil%20Color%20of%20the%20cursor)), `placeholder` (gray hint text shown when empty) and `placeholderColor` ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=viewOffset%20number%200%20The%20horizontal,nil%20Color%20of%20the%20cursor)), `pattern` (Lua pattern string for input validation) ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=focusedBackground%20color%20blue%20Background%20color,nil%20Color%20of%20the%20cursor)), and `replaceChar` (if set to a character like `"*"`, the input will mask its output – useful for password fields) ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=pattern%20string%3Fnil%20Regular%20expression%20pattern,for%20password%20fields)). There are also `focusedBackground`/`focusedForeground` colors to indicate focus state ([Input : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Input.html#:~:text=placeholder%20string,expression%20pattern%20for%20input%20validation)). The Input element emits `onChange(newText)` events (not listed in the reference, but available) whenever its text changes, as well as `onEnter` when it gains focus and `onKey`/`onChar` events as it’s a focusable element. You can call `input:setValue("new text")` or simply `input.text = "..."` to programmatically change the text.
- **Slider:** A horizontal or vertical slider for numeric input ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=This%20is%20the%20slider%20class,customizable%20colors%20and%20value%20ranges)). The slider consists of a track and a draggable handle. Properties: `horizontal` (bool, true by default meaning a left-right slider; false makes it vertical) ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Property%20Type%20Default%20Description%20step,Color%20of%20the%20slider%20handle)), `step` (current position of the handle along the track, from 1 up to the slider’s length) ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Properties)), and `max` (the maximum value represented by the full track, default 100) ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Property%20Type%20Default%20Description%20step,Color%20of%20the%20slider%20handle)). The slider’s value thus ranges 0 to `max`, and you can get it via `slider:getValue()` which maps the handle position to that range ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Method%20Returns%20Description%20Slider%3AgetValuenumber%20Gets,mapped%20to%20the%20max%20range)) ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Slider%3AgetValue)). Visual properties: `barColor` (the track color) and `sliderColor` (the handle color) ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=horizontal%20boolean%20true%20Whether%20the,Color%20of%20the%20slider%20handle)). Event: `onChange(value)` fires when the slider is moved by the user (value is the new value in [0, max] range) ([Slider : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Slider.html#:~:text=Events)). Sliders are great for adjusting percentages or ranges (e.g. volume control).
- **ProgressBar:** A non-interactive progress indicator (a filled bar). You update it programmatically to show progress of tasks. Properties: `progress` (0–100, percent filled) ([ProgressBar : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/ProgressBar.html#:~:text=Properties)), `progressColor` (color of the filled portion) ([ProgressBar : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/ProgressBar.html#:~:text=showPercentage%20boolean%20false%20Whether%20to,percentage%20text%20in%20the%20center)), and `showPercentage` (if true, displays a “XX%” text in the middle of the bar) ([ProgressBar : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/ProgressBar.html#:~:text=Property%20Type%20Default%20Description%20progress,percentage%20text%20in%20the%20center)). You typically set `progress` value via `bar:setProgress(value)` (or direct property) during your program’s execution to update the bar.

#### Selection and Menu Controls
- **List:** A scrollable list of text items, where each item can be selected (like a listbox) ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=This%20is%20the%20list%20class,rendering%2C%20separators%2C%20and%20selection%20handling)). The List can optionally allow multiple selections. Properties: `items` (a table array of the items to display) ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=Properties)). Each item in the list can be a simple string or a table with custom fields (for example, an item could be `{ text="Option1", selected=true }` to pre-select it). The list also has `selectable` (bool, default true – if false, items are not highlightable) and `multiSelection` (bool, default false – set true to allow selecting multiple items with e.g. Ctrl-click in CraftOS-PC) ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=items%20table,Text%20color%20for%20selected%20items)). It manages scrolling internally; use `list:scrollToTop()` / `scrollToBottom()` to programmatically scroll ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=List%3Aclear%20List%20Clears%20all%20items,the%20list%20to%20the%20top)). Colors: `selectedBackground` and `selectedForeground` for the highlight of selected items ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=multiSelection%20boolean%20false%20Whether%20multiple,Text%20color%20for%20selected%20items)). **Events:** `onSelect(index, item)` is fired when the user selects or activates an item ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=Events)). The List API provides helpers like `addItem(text)` to add entries ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=Method%20Returns%20Description%20List%3AaddItem%20List,callback%20for%20the%20select%20event)), `removeItem(index)` ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=List%3AgetSelectedItem%20table%3FGets%20first%20selected%20item,an%20item%20from%20the%20list)), `clear()` to clear all items ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=Method%20Returns%20Description%20List%3AaddItem%20List,callback%20for%20the%20select%20event)), and `getSelectedItem()` / `getSelectedItems()` to retrieve the currently selected entries ([List : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/List.html#:~:text=List%3Aclear%20List%20Clears%20all%20items,the%20list%20to%20the%20top)).
- **Dropdown:** A drop-down combo box, which is essentially a compact list that expands on click. It displays a chosen value and when clicked, opens a list of options for the user to select one ([Dropdown : List | Basalt](https://basalt.madefor.cc/references/elements/Dropdown.html#:~:text=Dropdown%20%3A%20List)). Properties: `isOpen` (bool, whether the dropdown list is currently expanded) ([Dropdown : List | Basalt](https://basalt.madefor.cc/references/elements/Dropdown.html#:~:text=Properties)), `dropdownHeight` (how many items to show when expanded before scrolling) ([Dropdown : List | Basalt](https://basalt.madefor.cc/references/elements/Dropdown.html#:~:text=Property%20Type%20Default%20Description%20isOpen,to%20show%20for%20dropdown%20indication)), `selectedText` (the text to show when nothing is selected; often a prompt like "Select...") ([Dropdown : List | Basalt](https://basalt.madefor.cc/references/elements/Dropdown.html#:~:text=Property%20Type%20Default%20Description%20isOpen,to%20show%20for%20dropdown%20indication)), and `dropSymbol` (the character to indicate the dropdown, default is a downward triangle `\31`) ([Dropdown : List | Basalt](https://basalt.madefor.cc/references/elements/Dropdown.html#:~:text=Property%20Type%20Default%20Description%20isOpen,to%20show%20for%20dropdown%20indication)). You populate a Dropdown by adding items (it inherits from List, so you can use `dropdown:addItem("Choice")` similarly). When an item is chosen, it triggers the `onSelect` event (from List) and the dropdown closes, showing the selected item’s text in the field. Dropdowns are useful for saving space when selecting from many options.
- **Menu:** A horizontal menu bar, typically for top-of-window menus (like “File, Edit, …”). It is essentially a single-row list of items that can include separators ([Menu : List | Basalt](https://basalt.madefor.cc/references/elements/Menu.html#:~:text=Menu%20%3A%20List)). You configure it with `menu:setItems({...})`, providing an array of items where each item is a table with properties like `{text="File", callback=function() ... end}` or `{separator=true}` for a vertical separator line ([Menu : List | Basalt](https://basalt.madefor.cc/references/elements/Menu.html#:~:text=Menu%3AsetItems)). The Menu will call an item’s `callback` function when that menu item is clicked. It has a `separatorColor` property to set the color of separator dividers ([Menu : List | Basalt](https://basalt.madefor.cc/references/elements/Menu.html#:~:text=Properties)). Menu items are displayed side by side; if they exceed the width, the menu may scroll or truncate (depending on implementation). The Menu class is built on List but specialized for single-row use ([Menu : List | Basalt](https://basalt.madefor.cc/references/elements/Menu.html#:~:text=Menu%20%3A%20List)). Use this for classic menu bars or toolbars.
- **Table:** A grid/table view for displaying tabular data with multiple columns ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Table%20%3A%20VisualElement)). You define the columns and then provide data rows. Properties: `columns` – a table of column definitions, each like `{ name="Col1", width=10 }` for the column header text and width ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Properties)). `data` – an array of rows, where each row is itself an array of values corresponding to columns ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Property%20Type%20Default%20Description%20columns,number%3Fnil%20Currently%20selected%20row%20index)). The table will render column headers and rows beneath, with optional grid lines. It supports selecting a row (with `selectedRow` property storing the currently selected row index) ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Property%20Type%20Default%20Description%20columns,desc)). Visual properties include `headerColor` (color for header background), `selectedColor` (highlight for selected row), and `gridColor` (color of grid lines between cells) ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Property%20Type%20Default%20Description%20columns,desc)). The Table supports sorting: clicking a column header will sort by that column (Basalt tracks `sortColumn` and `sortDirection` internally ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=headerColor%20color%20blue%20Color%20of,number%200%20Current%20scroll%20position))). You can also invoke sorting via `table:sortData(columnIndex)` to sort the data programmatically ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Method%20Returns%20Description%20Table%3AsortData%20Table,data%20by%20the%20specified%20column)) ([Table : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Table.html#:~:text=Table%3AsortData)). (This toggles `sortDirection` between "asc"/"desc".) The Table is scrollable vertically if there are more rows than fit; use arrow keys or mouse scroll on it. *Note:* The Table currently does not emit a dedicated onSelect event in docs (it may reuse onClick to handle row selection).
- **Tree (Treeview):** A hierarchical tree control for displaying nested data (like folders/files, or any outline) ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=Tree%20%3A%20VisualElement)). Nodes can be expanded or collapsed. Properties: `nodes` – the data structure for the tree, given as a nested table of nodes. Each node is typically a table `{ text="Node Label", children={...} }` (and children in turn have their own children, etc.) ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=Properties)). The Tree view renders these with indentation. It keeps track of `expandedNodes` (a set/table of which node entries are currently expanded) ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=properties%20selectedNode%20table%3Fnil%20Currently%20selected,Background%20color%20of%20selected%20node)), `selectedNode` (the currently selected node table, or nil if none) ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=nodes%20table,Background%20color%20of%20selected%20node)), and scroll positions (`scrollOffset` vertical and `horizontalOffset` if needed) ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=properties%20selectedNode%20table%3Fnil%20Currently%20selected,Background%20color%20of%20selected%20node)). Colors: `nodeColor` for normal nodes text, `selectedColor` for the background of the selected node ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=expandedNodes%20table,Background%20color%20of%20selected%20node)). **Events:** Tree provides `onSelect(node)` via `Tree:onSelect(fn)` to notify when a node is selected ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=Method%20Returns%20Description%20Tree%3AcollapseNode%20Tree,between%20expanded%20and%20collapsed%20state)). **Methods:** You can expand/collapse nodes programmatically: `tree:expandNode(node)` and `tree:collapseNode(node)` ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=Method%20Returns%20Description%20Tree%3AcollapseNode%20Tree,between%20expanded%20and%20collapsed%20state)) (or `toggleNode`). There is also `tree:getNodeSize()` which might return total node count or depth (useful for layout) ([Tree : VisualElement | Basalt](https://basalt.madefor.cc/references/elements/Tree.html#:~:text=Tree%3AcollapseNode%20Tree%20Collapses%20a%20node,between%20expanded%20and%20collapsed%20state)). The user can click the little expand [+] or collapse [-] markers (Basalt handles those in the render), or double-click nodes depending on implementation. Use Tree when you need to show hierarchical information to the user in an organized way.

#### Other Specialized Elements
- **Graph / Graphic:** *(New in Basalt 1.7)* A graphical canvas element intended for drawing graphs, charts, or images. The **Graph** (also called “Graphic” in some posts) allows you to plot data points or possibly display image files in NFP (NFP = Paint format) within a Basalt UI. This was introduced in v1.7 ([Release Basalt v1.7 · Pyroxenium/Basalt · GitHub](https://github.com/Pyroxenium/Basalt/releases/tag/v1.7#:~:text=,Reworked%20the%20XML%20System)). While official documentation is limited, a Graph likely has methods to plot lines or set pixels and might support multiple data series. Use Graph if your application needs custom drawings (for example, real-time monitoring graphs).
- **Switch:** *(Possible addition)* A toggle switch (as mentioned in community updates) that behaves like a checkbox but with a slider appearance (ON/OFF). Not officially documented in the latest reference, but you can simulate a switch with a Checkbox or wait for official support. (If using a dev version that includes Switch, it would have a `checked` property similar to Checkbox.)
- **Image:** Another community-mentioned addition (Basalt supports an image element in newer versions). An Image element would allow displaying an image (like a logo or icon) given image data. In practice, images can be handled by drawing to a Label or Graph using custom characters/colors. Check Basalt’s repository examples for image usage if needed.

*Tip:* Many of the above elements can contain text (Button, Label, Checkbox, etc.). Basalt uses CC:Tweaked’s color palette (0-15 or color constants) for `foreground`/`background` and any color properties. You can use the global `colors` API (e.g. `colors.red`) when setting these properties.

### Event Handling Example

To illustrate event callbacks, consider a text Input and a Label that displays live count of characters typed:

```lua
local input = main:addInput()
               :setPosition(2, 2)
               :setSize(20, 1)
               :setPlaceholder("Type here...")

local info = main:addLabel()
               :setPosition(2, 4)
               :setText("Length: 0")

-- Update label whenever input text changes:
input:onChange(function(self, newValue)
    info:setText("Length: " .. #newValue)
end)
```

Here, `onChange` is used on the Input to react whenever the user types or deletes a character (changing the input’s text). The callback updates the Label below to show the length of the current input. This demonstrates Basalt’s reactive event model – you register callbacks for events of interest and Basalt triggers them appropriately as the user interacts.

## Advanced Features and Modules

Beyond basic GUI widgets, Basalt provides advanced systems to make your UI development more powerful and manageable: **State management**, **Animations**, **Themes**, **XML UI definition**, and a **Plugin system** for extension. These are part of Basalt’s design to support complex applications.

### State Management (Reactive Data Binding)

Basalt includes a built-in **state management system** that allows you to store data values and automatically update UI elements when those values change. A **State** is essentially a named variable tied to a frame (or container) that can trigger reactive updates.

**Defining States:** You initialize state values by calling `frame:initializeState(name, defaultValue, triggerRender)` ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=lua)). For example: 

```lua
main:initializeState("count", 0)
```

This creates a state called `"count"` with initial value 0. The optional third parameter (triggerRender) if true will force a re-render whenever the state changes (usually leave it default true for visual states). After initialization, you can use:
- `frame:setState(name, newValue)` to update a state ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,name)) ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,name)).
- `frame:getState(name)` to retrieve the current value ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,name)) ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,name)).

**Computed States:** You can define a state that is derived from other states by using `frame:computed(name, function(self) ... end)` ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,based%20on%20other%20states%20end)). The function should compute and return a value based on one or more other states. Basalt will automatically re-calc it when dependencies change. For example, one could define an `"isValid"` state that depends on three other form field states (as shown in the code below). Computed states are great for things like form validation logic or dynamic aggregates.

**State Change Listeners:** Use `frame:onStateChange(stateName, function(self, newValue) ... end)` to run code when a specific state changes ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,React%20to%20state%20changes%20end)). This is often used to update UI appearance based on state. Notably, **any UI property can be bound to a state as well** by using dynamic property syntax (e.g., set a Label’s text to an expression that references a state variable, or call a method in an onStateChange to update an element).

**Example:** Consider a simple form with two input fields and a submit button. We want the button to be enabled (green) only when both inputs have some content (non-empty). Using states:

```lua
local form = main:addFrame()
form:initializeState("name", "")
form:initializeState("email", "")
form:computed("formValid", function(self)
    local nm = self:getState("name")
    local em = self:getState("email")
    return (#nm > 0) and (#em > 0 and string.find(em, "@"))
end)

local nameInput = form:addInput():setPosition(1,1):setSize(20,1)
local emailInput = form:addInput():setPosition(1,3):setSize(20,1)
local submitBtn = form:addButton():setPosition(1,5):setText("Submit")

-- Update states on input change
nameInput:onChange(function(self, val) form:setState("name", val) end)
emailInput:onChange(function(self, val) form:setState("email", val) end)

-- React to validity state: color the button
form:onStateChange("formValid", function(self, isValid)
    submitBtn:setBackground(isValid and colors.lime or colors.gray)  -- green if valid, gray if not
    submitBtn:setActive(isValid)  -- (hypothetical method: enable/disable button)
end)
```

In this example, we created two states `"name"` and `"email"` to hold the field values, and a computed `"formValid"` state that checks that name is non-empty and email contains an `"@"` ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=local%20form%20%3D%20main%3AaddFrame%28%29%20%3AsetSize%28,username)) ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,value%29%20end)). Each Input’s onChange updates the corresponding state. Then an `onStateChange` on `"formValid"` toggles the Submit button’s color and active state. This way, the UI automatically reflects validation logic without manual checks after every keystroke – Basalt handles the reactivity. 

**Best Practices for State:** 
- Initialize all needed states when creating the component (with meaningful default values) ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=1)).
- Use computed states for any value that depends on multiple other states (to avoid redundant manual updates) ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=2)).
- Use `onStateChange` to perform side effects (like UI feedback) whenever a state transitions ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,Consider%20batching%20multiple%20state%20updates)).
- Prefer updating via `setState` rather than directly modifying variables, so that Basalt knows to notify listeners ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=,Consider%20batching%20multiple%20state%20updates)).
- States are stored per frame; if you have nested frames, state names can be reused in different frames without conflict.

In summary, the state system enables a **reactive UI** pattern, where UI elements reflect application data. This can greatly simplify keeping UI in sync with logic.

### Animation System (Smooth UI Animations)

Basalt features a powerful **animation API** to animate properties of UI elements. You can animate movement, resizing, color changes, text changes, etc., with support for easing and sequencing. This allows you to create more dynamic and polished interfaces (think of a menu smoothly sliding in, or a button fading when pressed).

**Creating an Animation:** Any visual element has an `:animate()` method. Calling it returns an **Animation object** on which you can queue up animation commands ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=,in%20seconds)). The common animation methods include:
- `:move(x, y, duration)` – animate the element’s position to the given (x,y) over `duration` seconds ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=element%3Aanimate,Animate%20text)).
- `:moveOffset(dx, dy, duration)` – animate the element’s offset (for scrolling containers) by the given delta ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=element%3Aanimate,Animate%20text)).
- `:resize(width, height, duration)` – smoothly change the element’s size to the given dimensions ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3Amove,Animate%20text)).
- `:morphText(property, targetText, duration)` – animate a text property (like the `text` of a Label) to another string, gradually morphing each character ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3AmoveOffset,Animate%20text)).
- `:typewrite(property, text, duration)` – animate text by “typing” it out one character at a time over the duration ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3AmoveOffset,Animate%20text)).
- `:fadeText(property, text, duration)` – animate text by fading the old text out and new text in ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3Aresize,Animate%20text)).
- `:scrollText(property, text, duration)` – animate text by scrolling old out and new in ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3AmorphText%28property%2C%20targetText%2C%20duration%29%20%20,Animate%20text)).

(All the above `property` parameters refer to which text field to animate – e.g. `"text"` for a Label’s main text, or other properties if the element has multiple text fields.)

After queuing the animation steps, you call `:start()` on the Animation to begin playing it ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=lua)). For example:

```lua
-- Slide a panel in from the left over 1 second:
panel:setX(-30)                         -- start off-screen (assuming width ~30)
panel:animate()
     :move(2, panel.y, 1.0)             -- animate to x=2 at current y in 1 second
     :start()
```

You can also capture the returned Animation in a variable to control it:
- `anim:pause()` – pause the animation mid-way ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=local%20anim%20%3D%20element%3Aanimate,Start%20the%20animation)).
- `anim:resume()` – resume a paused animation ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3Astart,Start%20the%20animation)).
- `anim:stop()` – stop and reset the animation ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3Astart,Start%20the%20animation)).

**Easing:** By default animations use a linear easing. Basalt supports easing functions like `easeIn`, `easeOut`, `easeInOut` for smoother motion ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=Basalt%20is%20now%20able%20to,easeIn%2C%20easeOut%2C%20easeInOut)). These can be specified as an optional last parameter to the animation methods (for example, `:move(x,y,duration,"easeOut")`). Eased animations will start or end slowly for a nicer effect.

**Sequences and Chains:** If you call multiple animation methods in one chain without interruption, they will all start simultaneously. To run animations back-to-back, Basalt provides a `:sequence()` method. In an animation chain, inserting `:sequence()` creates a break so that subsequent animations wait until the previous ones finish before starting ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=,simultaneously%20%3Astart)) ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=element%3Aanimate,simultaneously%20%3Astart)). For example:

```lua
element:animate()
    :move(10, 5, 1)      -- move to (10,5) in 1s
    :resize(5, 5, 1)     -- AND resize at the same time (no sequence in between)
    :sequence()          -- wait for above two to finish
    :morphText("text", "Done", 0.5)
    :start()
```

In this example, the move and resize happen concurrently (over the first 1 second), then after they complete, the text morph happens ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=,simultaneously%20%3Astart)) ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=element%3Aanimate,simultaneously%20%3Astart)). You can create very complex timelines by grouping steps with `sequence()`. If you want multiple animations to happen simultaneously after a wait, you can do something like `:sequence():move(...):morphText(...)` without another sequence between move and morph – those two will run together after the initial sequence wait ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=,simultaneously%20%3Astart)).

**onDone Callback:** You can also attach a callback for when an entire animation sequence finishes using `:onDone(function() ... end)` in the chain ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=%3Asequence%28%29%20%3Amove%285%2C%2010%2C%200,%3Astart)). This is useful to trigger some action after a lengthy animation completes (e.g. remove an element after it fades out).

**Usage Example:** To illustrate, suppose we want a label to fade in new text. We can do:

```lua
label:animate()
     :fadeText("text", "Hello World", 1.5)
     :start()
```

This will animate the label’s `text` from whatever it was to `"Hello World"` over 1.5 seconds with a fading effect. Or, to bounce a button in a square path:

```lua
button:animate()
    :move(button.x + 5, button.y, 0.3)   -- move right
    :sequence()
    :move(button.x + 5, button.y + 2, 0.3)  -- then down
    :sequence()
    :move(button.x, button.y + 2, 0.3)   -- then left
    :sequence()
    :move(button.x, button.y, 0.3)       -- then up back to start
    :onDone(function() print("Bounce loop done") end)
    :start()
``` 

This demonstrates chaining and sequencing of multiple moves ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=,Then%20up%20%3AonDone%28function)) ([Basalt Animations | Basalt](https://basalt.madefor.cc/guides/animations.html#:~:text=element%3Aanimate%28%29%20%3Amove%2810%2C%205%2C%200,Then%20up%20%3AonDone%28function)).

Animations can greatly enhance the user experience. For example, you could animate a sidebar frame sliding in/out for a menu, buttons changing color on hover or click (via a short color fade animation), or list items smoothly scrolling into place. Basalt’s animation system makes these effects relatively easy to script. Remember to call `:start()` to kick them off after building the sequence. You can run multiple animations on different elements simultaneously – Basalt will handle them in its update loop.

### Theming and Styles

Basalt supports a **theming system** that allows you to define a consistent look and feel across your UI, and even switch themes at runtime. The theme system is provided via a plugin (the **ThemeAPI**).

With theming, you can define default styles for certain element types or for elements with specific names. For example, you might create a theme that sets all Buttons to have a blue background and white text by default, and all Labels to use yellow text, etc. Then applying the theme will automatically give elements those colors unless overridden.

**Applying a Theme:** An element can have `:applyTheme()` called on it to apply the current global theme to that element (and optionally its children) ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/theme.html#:~:text=Method%20Returns%20Description%20BaseElement%3AapplyTheme%20BaseElement,theme%20properties%20for%20the%20element)) ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/theme.html#:~:text=BaseElement%3AapplyTheme)). In practice, you typically set the theme globally and Basalt will apply it when creating elements.

**Theme API:** `basalt.getAPI("ThemeAPI")` gives access to theme functions ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/theme.html#:~:text=ThemeAPI)):
- `ThemeAPI.loadTheme(filepath)` – Load a theme from a JSON file.
- `ThemeAPI.setTheme(themeTable or name)` – Apply a theme (either provide a theme table or perhaps a name if pre-registered) ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/theme.html#:~:text=Functions)).
- `ThemeAPI.getTheme()` – Get the currently active theme’s data ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/theme.html#:~:text=ThemeAPI)).

Themes are usually defined in a JSON structure mapping element selectors to style properties. For instance, a theme file might specify styles for `"Button"` type, or for `"#submitButton"` (an element with name or id "submitButton"), etc. Once loaded and set, those styles will reflect on the UI.

**Example:** A simple theme might declare that all buttons have `foreground=colors.white` and `background=colors.gray`, with a special case for a button named "dangerBtn" to be red. Loading that theme and doing `ThemeAPI.setTheme(...)` would cause Basalt to update existing elements to match (and new elements to inherit those styles on creation, since Basalt’s elements check the theme in their init).

If you change theme at runtime via `setTheme()`, you can call `frame:applyTheme()` on your top frame to re-apply the new styles to everything.

The theming system supports **inheritance** (one theme can extend another), **named styles**, and dynamic switching, making it convenient to implement light/dark mode or user-selectable skins ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/theme.html#:~:text=BaseElement)). By separating style from code, themes help keep a consistent design and allow changing the UI appearance without altering the main logic.

### Defining UI with XML (Declarative UI)

In addition to writing Lua code to construct interfaces, Basalt offers an **XML parser** that can create UI layouts from an XML description ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=XML%20in%20Basalt)). This allows you to define your UI in a markup format (similar in spirit to HTML or Android’s XML layouts), which some may find more readable or easier to maintain for complex interfaces.

**Basic Usage:** You can call `frame:loadXML(xmlString, scopeTable?)` to parse and create UI elements from an XML string (or file) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=local%20main%20%3D%20basalt)). For example:

```lua
local xmlData = [[
<frame width="30" height="10">
    <button text="Click me!" x="2" y="2"/>
</frame>
]]
main:loadXML(xmlData)
```

This would create a Frame 30x10 and within it a Button at (2,2) with text "Click me!" ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=,%3C%2Fframe%3E)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=main%3AloadXML%28%5B%5B%20%3Cframe%20width%3D,%3C%2Fframe%3E)). The XML tags correspond to element types (frame, button, label, etc.), and attributes correspond to properties (numeric strings will be converted to numbers, `"true"/"false"` to booleans, color names to their Color constants, etc. ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=xml)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=%3Cbutton%20x%3D,))). The root tag is usually a `<frame>` (or `<baseframe>`).

**Scope and Variables:** You can pass a `scope` table as the second argument to `loadXML` which provides variables and functions that the XML can reference ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=Working%20with%20Variables)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=main%3AloadXML%28%5B%5B%20%3Cframe%3E%20%3Clabel%20text%3D,%3C%2Fframe)). In the XML, you can insert `${...}` expressions to use values from this scope ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=,sensitive%203.%20Expressions)). For example:

```lua
local scope = {
  title = "My App",
  handleClick = function(self) self:setText("Clicked!") end
}
main:loadXML([[
  <frame>
    <label text="${title}"/>
    <button text="Click" onClick="handleClick"/>
  </frame>
]], scope)
```

In this snippet, the Label’s text will be set to the value of `scope.title` (“My App”) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=lua)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=main%3AloadXML%28%5B%5B%20%3Cframe%3E%20%3Clabel%20text%3D,%3C%2Fframe%3E%20%5D%5D%2C%20scope)). The Button has an attribute `onClick="handleClick"`, which tells Basalt to use the `handleClick` function from the scope table as the onClick handler for that button ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=lua)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=%3Cbutton%20onClick%3D)). The special attribute `onEventName="functionName"` lets you assign event callbacks from scope by name. Alternatively, XML supports an inline `<onClick><![CDATA[ ... ]]></onClick>` block where you can write a Lua function body directly in the XML for the event ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=2)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=)). (The CDATA section is used to include Lua code without XML parsing issues.)

**Data Types:** The XML parser automatically interprets attribute values: e.g. `"5"` becomes number 5, `"true"` becomes boolean true, `background="blue"` becomes the color value for blue (using the CC `colors` table) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=xml)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=%3Cbutton%20x%3D,)). Strings with `${...}` are evaluated as expressions in the scope ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=xml)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=background%3D%22blue%22%20%20%20%20%3C%21,)). If an attribute should explicitly remain a string (e.g. you want the label text to literally be "${title}"), you’d have to escape or adjust accordingly.

**Event Handlers in XML:** As noted, you have two options:
1. Reference a scope function by name (simpler, keeps code in Lua file) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=1,Scope)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=main%3AloadXML%28%5B%5B%20%3Cbutton%20onClick%3D)).
2. Provide a function body inline using `<EventName>` tag with CDATA ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=xml)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=%3Cbutton%3E%20%3ConClick%3E%20%3C%21%5BCDATA%5B%20function%28self%29%20self%3AsetText%28,onClick)).

The first approach is typically cleaner – define the logic in Lua, just wire it up by name in XML.

**Considerations:** When using XML, your program flow might be: load the XML to build the UI, then perhaps manipulate some elements via code if needed (you can retrieve elements by id or other means – Basalt might provide functions to get elements by their id/name). The scope mechanism is important: only variables/functions provided in the scope table (or globally available) can be seen by the XML. It will not magically capture your local Lua variables unless you put them in the scope.

XML layout can make it easy to visualize nested structures, and you can tweak layout by editing the XML rather than Lua code. Some developers prefer this separation of structure from logic. Basalt’s XML is optional; you can always do everything in Lua if you prefer, but it’s a powerful addition.

### Plugin System and Extensibility

Basalt has been designed with a **modular plugin system** (introduced in v1.7) ([Release Basalt v1.7 · Pyroxenium/Basalt · GitHub](https://github.com/Pyroxenium/Basalt/releases/tag/v1.7#:~:text=,Reworked%20the%20XML%20System)). Many of the advanced features (animations, state, theme, debug, etc.) are implemented as plugins. This means they extend or modify Basalt’s base classes without the user having to explicitly call them. For instance, when you call `element:animate()`, internally the **Animations plugin** is providing that method to all VisualElements.

For most users, this is transparent – you just use the feature. But if needed, you can create custom plugins or access plugin APIs:
- The `plugins/` directory in Basalt contains plugin code. You can add your own plugin file there, and Basalt will load it on startup ([ElementManager | Basalt](https://basalt.madefor.cc/references/elementManager.html#:~:text=ElementManager)).
- `basalt.getAPI("YourPluginName")` can retrieve a table of functions your plugin exposes ([ElementManager | Basalt](https://basalt.madefor.cc/references/elementManager.html#:~:text=ElementManager)) (if any).
- The Basalt `ElementManager` handles loading all default elements and plugins on startup ([ElementManager | Basalt](https://basalt.madefor.cc/references/elementManager.html#:~:text=This%20class%20manages%20elements%20and,to%20get%20elements%20and%20APIs)). It ensures that when an element class is created, any plugin-defined hooks or extensions are applied to it.

As an example, the **Debug plugin** adds methods `BaseElement:debug(level)` and `BaseElement:dumpDebug()` that weren’t in the base class originally ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=Method%20Returns%20Description%20BaseElement.debug,Dumps%20debug%20information)) ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=BaseElement)). The **Reactive plugin** enables the dynamic property expressions (`"{...}"` syntax) by observing property changes and re-evaluating expressions ([Reactive | Basalt](https://basalt.madefor.cc/references/plugins/reactive.html#:~:text=Reactive)). These are seamlessly integrated.

For creating custom plugins, you’d typically define new methods or events for elements. Basalt’s wiki and examples (see the `pluginExample` file) can guide how to register a plugin. The plugin system makes Basalt flexible and allows community contributions to add features without altering Basalt’s core.

## Error Handling and Debugging in Basalt

When developing UIs, errors can happen (e.g. a callback throws an exception). Basalt provides mechanisms to catch and handle errors more gracefully than a bare ComputerCraft program might.

**Error Handling:** Basalt installs a global error handler that intercepts errors from within the `basalt.run()` loop. By default, if an error occurs in an event callback or Basalt code, Basalt will catch it and display an error message on the screen (so you’re not just dropped back to the shell with a Lua error). It will typically show a message with the error and, if enabled, a traceback. The `basalt.traceback` flag controls whether a full stack trace is shown ([ErrorHandler | Basalt](https://basalt.madefor.cc/references/errorManager.html#:~:text=Field%20Type%20Description%20tracebackEnabled%20,header%20of%20the%20error%20message)). If you set `basalt.traceback = true` (or call `basalt.LOGGER.setEnabled(true)` to enable logging to file), you can get detailed traces for debugging.

Basalt’s internal `ErrorHandler` (accessible via `basalt.getErrorManager()`) has a method `errorHandler.error(errMsg)` that formats and logs the error ([ErrorHandler | Basalt](https://basalt.madefor.cc/references/errorManager.html#:~:text=Method%20Returns%20Description%20errorHandler.error)). As a user, you normally don’t call this manually – it’s used by Basalt itself when something goes wrong. The error screen will usually show a header (like “An error occurred”) and the error message, optionally the traceback if toggled ([ErrorHandler | Basalt](https://basalt.madefor.cc/references/errorManager.html#:~:text=tracebackEnabled%20,header%20of%20the%20error%20message)). This helps identify which callback or line in your code caused the issue.

If you want to deliberately trigger an error (for testing the UI’s error overlay, for example), you could call `error("message")` inside an event – Basalt would catch it and use its ErrorManager to display it.

**Logging:** The Basalt `LOGGER` (Log module) can be used to output debug information. By default, logging might be disabled or just in-memory. You can enable log to file via `basalt.LOGGER.setLogToFile(true)` and set a path if needed ([Log | Basalt](https://basalt.madefor.cc/references/log.html#:~:text=Log.error%20,Sends%20a%20warning%20message)). The logger supports different levels:
- `Log.debug(msg...)` – for verbose debug messages ([Log | Basalt](https://basalt.madefor.cc/references/log.html#:~:text=Method%20Returns%20Description%20Log.debug%20,Sends%20a%20warning%20message)).
- `Log.info(msg...)` – informational messages.
- `Log.warn(msg...)` – warnings.
- `Log.error(msg...)` – error messages (these might also tie into the error handler) ([Log | Basalt](https://basalt.madefor.cc/references/log.html#:~:text=Method%20Returns%20Description%20Log.debug%20,Sends%20a%20warning%20message)).

All log messages are stored in an internal log history and can optionally be written to a file (the default log file is typically `.basalt.log` or similar, configurable via `_logFile`) ([Log | Basalt](https://basalt.madefor.cc/references/log.html#:~:text=Field%20Type%20Description%20_logs%20,The%20log%20levels)). You can use the logger in your own code to help debug state (those messages can be viewed in the debug console, discussed next). For example: `basalt.LOGGER.info("Opened settings menu")`.

**Debug Console and Tools:** Basalt has a **Debug plugin** that provides a built-in debug console overlay. You can toggle it at runtime to inspect what’s happening. The main methods are attached to the BaseFrame:
- `BaseFrame:showDebugLog()` – opens the debug log UI (likely a panel showing the log messages) ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=Method%20Returns%20Description%20BaseFrame.hideDebugLog,Toggles%20the%20debug%20log%20frame)).
- `BaseFrame:hideDebugLog()` – closes it ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=Method%20Returns%20Description%20BaseFrame.hideDebugLog,Toggles%20the%20debug%20log%20frame)).
- `BaseFrame:toggleDebugLog()` – toggle on/off.

When the debug log is visible, you can see the output of `Log.debug/info` etc., and possibly other stats. Additionally, `BaseElement:debug(level)` can be called on any element to enable verbose debug info for that element ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=Method%20Returns%20Description%20BaseElement.debug,Dumps%20debug%20information)). For example, `element:debug(1)` might draw outlines or print info about that element’s position, and higher levels might show more internal detail. `BaseElement:dumpDebug()` will dump debug details of an element to the log ([BaseElement | Basalt](https://basalt.madefor.cc/references/plugins/debug.html#:~:text=Method%20Returns%20Description%20BaseElement.debug,Dumps%20debug%20information)).

These tools are extremely useful during development. For instance, if an element isn’t appearing where you expect, you could call `element:debug(1)` on it to see if it’s being drawn off-screen or if its visible property is false, etc. The debug overlay might also highlight focused elements or show coordinate grids.

**Common Pitfalls & Solutions:** If your UI isn’t showing anything or responding, consider these debugging tips:
- **UI doesn’t display at all:** Make sure `basalt.run()` was called ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F)). This is the #1 cause of nothing happening.
- **Element not visible:** Check the list from the FAQ – verify the element’s `x,y` position is within its parent’s bounds, the parent/frame is large enough to contain it, the element’s `visible` property is true, and that it isn’t hidden behind another element with a higher z-index ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Check%3A)). Using the debug overlay or printing `element:getPosition()` can help. If layering is the issue, use `element:prioritize()` to bring it front ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=VisualElement%3AisInBounds%20boolean%20Checks%20if%20point,top%20of%20its%20parent%27s%20children)).
- **Text not showing or cut off:** Perhaps the element’s size is too small (e.g. a Label with `autoSize=false` needs a width set). Or colors might be the same as background (check `foreground` vs `background` colors).
- **Interactive element not responding:** Is it possibly not within an active frame or its parent frame is not active? If using multiple frames, ensure you focused or set active the correct one with `basalt.setActiveFrame()`. Also, confirm the event in question is being fired (e.g. CraftOS turtles don’t emit mouse_click for monitors by default, etc.). Keyboard input requires the element to have focus – maybe call `someInput:focus()` to give it focus programmatically, or click it.
- **Error messages appearing:** If you see Basalt’s error screen, read the message and traceback (if on). It often pinpoints a line in your script or a specific event callback. Use that along with your code to fix the bug. Remember you can toggle `basalt.traceback` to true for more details ([ErrorHandler | Basalt](https://basalt.madefor.cc/references/errorManager.html#:~:text=Field%20Type%20Description%20tracebackEnabled%20,header%20of%20the%20error%20message)).
- **Performance issues:** Basalt is optimized to only redraw on changes ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=,elements%20that%20actually%20use%20them)). If you’re experiencing lag, check if you are calling `:update()` in a tight loop unnecessarily or spamming state changes. Use `basalt.schedule()` for heavy computations to offload them. The Benchmark plugin (accessible via references) can measure frame render times if needed.
- **Monitors not updating:** If drawing to a monitor, ensure you created a BaseFrame for that monitor (either via `createFrame()` + some method to attach, or using `setMonitor(side)` on a frame ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=The%20old%20version%20of%20basalt,side))), and that you call `basalt.run()` *after* setting that up. Also ensure the computer has a wired modem if it’s a peripheral and that the monitor is correctly attached (basalt won’t know about the monitor if it’s not a peripheral of that computer or not attached via wired modem).

By leveraging Basalt’s logging and debug view, you can inspect these issues at runtime. For example, toggling the debug log will let you see if events are being registered or if any errors were silently logged. The debug tools can dramatically reduce the guesswork in fixing UI problems.

## Best Practices for Effective Basalt Usage

To make the most of Basalt and avoid common mistakes, keep these **best practices** in mind:

- **Always call `basalt.run()`** after setting up your UI ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F)). Without it, nothing will happen. Do any initialization (like populating lists or setting up state) *before* calling `run`, because after `run` the UI loop is running.
- **Group UI setup logically:** You can create sub-frames or use container frames to logically group parts of your interface (e.g. a sidebar frame vs main content frame). This makes management easier (you can show/hide an entire frame, etc., instead of many individual elements).
- **Use dynamic sizing/positioning** for responsive layouts ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=How%20do%20I%20handle%20screen,resizes)). Instead of hardcoding absolute sizes that may not adapt, consider using percentage-based or relative expressions (`"{parent.width - 5}"` etc.) for positions and sizes. This ensures your UI looks good on different terminal sizes or if a window is resized. You can also use the Flexbox container to automatically lay out children without manual coordinate calculations.
- **Leverage the State system** for complex UIs. Keep the application data in state variables and let Basalt update the UI via computed states and onStateChange, instead of manually tweaking multiple elements every time something changes. This leads to cleaner separation of logic and presentation. For example, in a multi-step form, use a state to track the current step and have UI elements react to that state (show/hide sections, etc.) rather than writing imperative code to show/hide each time.
- **Initialize states early:** If you plan to use states, initialize them when you create the frame (with sensible defaults) ([State Management in Basalt | Basalt](https://basalt.madefor.cc/guides/states.html#:~:text=1)). This avoids nil states later and you can set up onStateChange handlers before values change.
- **Don’t block the event loop in handlers:** Keep your event callbacks (onClick, etc.) short and non-blocking. If you need to perform a long operation (e.g. querying a web API or doing a heavy computation), use `basalt.schedule()` to run it in a separate coroutine ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)). This way the UI remains responsive (the rest of the UI can still update or animations can play while the task runs). If you block inside an event handler (e.g. a for-loop that takes 5 seconds), the UI will freeze for 5 seconds. So offload or break up heavy work.
- **Use `onChange` and other events appropriately:** For text input, `onChange` gives you live updates – use it for immediate feedback (like form validation) but be mindful that it fires on every keystroke. For a less aggressive approach, you could use `onLoseFocus` (onBlur) or a submit button. Similarly, use `onSelect` for list selection changes, `onClick` for simple button presses, etc.
- **Consistent styling via Themes:** Instead of setting colors for every element, consider defining a theme (even if just in code by iterating elements) or at least reusing style constants. This makes it easier to adjust later or implement light/dark mode. Basalt’s theme plugin is there to help – using it can save time especially for large UIs where consistency is important.
- **Z-index and layering:** If you have overlapping elements (like a dropdown that should appear above others), ensure their `z` property is higher. Containers typically handle child ordering; if needed, call `:prioritize()` on an element to bring it to front ([VisualElement : BaseElement | Basalt](https://basalt.madefor.cc/references/elements/VisualElement.html#:~:text=VisualElement%3AisInBounds%20boolean%20Checks%20if%20point,top%20of%20its%20parent%27s%20children)). Use this when showing pop-up dialogs or menus.
- **Clean up if needed:** Basalt will generally clean up on exit, but if you dynamically create and remove elements at runtime, ensure you call `element:destroy()` when removing an element to free its resources properly ([BaseElement : PropertySystem | Basalt](https://basalt.madefor.cc/references/elements/BaseElement.html#:~:text=Method%20Returns%20Description%20BaseElement.defineEvent,and%20calls%20all%20registered%20callbacks)). This is rarely an issue in short-lived programs, but in long-running ones it’s good practice.
- **Test on actual CC environment:** Some features like mouse hover or certain events behave differently on CraftOS-PC vs in-game ComputerCraft. If your program will run in-game, test it there with actual monitor peripherals (especially for things like `monitor_touch` events and multi-monitor usage).
- **Read the docs and use the community:** Basalt is actively developed, and the community (GitHub, Discord) often provides useful examples. If something isn’t working as expected, chances are someone on the Discord or forums has encountered it and can provide insight. The Basalt documentation site (which this guide is based on) has reference pages for each element and guide sections for animations, state, etc. – use them for deeper details on each feature.

## Common Pitfalls and Version-Specific Notes

Despite Basalt’s user-friendly design, developers occasionally run into these **common pitfalls**:

- **Forgetting to run the UI loop:** (Worth repeating) Not calling `basalt.run()` or forgetting that a `basalt.run()` call is blocking. Make sure it’s at the end of your program (or if you need your own loop, integrate with `basalt.update()` properly). If the UI isn’t coming up at all, this is the first thing to check ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F)).
- **Misusing relative coordinates:** Remember that all child element coordinates (`x,y`) are relative to their **parent** container, not the overall screen unless the parent is the BaseFrame. If you place a button inside a frame that itself is at (5,5), and you want the button at screen coords (6,6), you should set the button’s position to (2,1) (because within the frame, (1,1) is at overall (5,5)). Getting this wrong can make elements appear offset or not appear at all if placed outside parent bounds ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Check%3A)). Tip: If an element isn’t visible, double-check its parent’s position/size.
- **Element name conflicts:** If you give multiple elements the same `name` or `id`, functions that fetch by name (if you use them) might return the first match. Ensure unique identifiers if you rely on them. Alternatively, keep references to elements in Lua variables (which is straightforward since `addX()` returns the element).
- **Not accounting for terminal size:** ComputerCraft terminals (and monitors) vary in size (51x19 for advanced computer, etc.). If your Basalt UI is larger than the terminal, it will be cut off. Consider using `%` based sizing or checking `term.getSize()` to adapt. Or document that a larger monitor is required.
- **Using unsupported features on vanilla CC:** Basalt does not support vanilla ComputerCraft 1.7.10 (and some features like mouse hover, multiple monitor attachments, etc., rely on CC:Tweaked enhancements) ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=There%20are%20some%20objects%20i,there%20are%20some%20missing%20information)). Always use CC:Tweaked (which most modpacks include nowadays) or CraftOS-PC for development. If running in CraftOS-PC, you get extras like draggable windows with the mouse, which won’t apply in the actual Minecraft mod environment unless using a touch monitor for drag.
- **Monitor input differences:** On a multishell (advanced computers) or multi-monitor setup, keep in mind how ComputerCraft differentiates inputs. A monitor click comes as a `monitor_touch` event with side and coords, whereas a normal `mouse_click` is for the terminal. Basalt abstracts this mostly – if your BaseFrame is tied to a monitor via `setMonitor`, Basalt will handle `monitor_touch` as onClick for that frame. But if you mirror or have multiple frames, ensure the correct events go to each frame (Basalt’s `getActiveFrame(term)` helps route events to frames on different terms) ([basalt | Basalt](https://basalt.madefor.cc/references/main.html#:~:text=basalt)).
- **Case sensitivity and syntax in XML:** If using XML, remember that event names in attributes are case-sensitive (`onClick` not `onclick`), and the scope function names must match exactly ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=,Event%20Handlers)) ([XML in Basalt | Basalt](https://basalt.madefor.cc/guides/xml.html#:~:text=,sensitive%203.%20Expressions)). Also, wrap inline Lua in `<![CDATA[]]>` properly or the XML parser may choke on symbols. A common mistake is forgetting to pass the scope table or including something in XML that isn’t in scope, leading to a runtime error (e.g. `onClick="doThing"` but `doThing` isn’t defined in scope).
- **Running on older Basalt version docs:** Ensure you refer to the latest docs for the version you’re using. Basalt v1.7 introduced breaking changes (object system rework, plugin separation) ([Release Basalt v1.7 · Pyroxenium/Basalt · GitHub](https://github.com/Pyroxenium/Basalt/releases/tag/v1.7#:~:text=,Reworked%20the%20XML%20System)), so code from older tutorials (pre-1.7) might use deprecated calls (for example, older code might use `basalt.autoUpdate()` instead of `basalt.run()`, or might not have the state system). Always adjust to the current API. If you see a community example calling something that doesn’t exist, check if it’s for a different version.
- **Memory and cleanup:** If your program creates lots of elements dynamically (say dozens of list items or windows) and removes them, be mindful to destroy elements or they’ll linger in memory. Basalt does garbage collection when frames close, but within a running session, remove heavy objects if no longer needed.
- **Coordinates vs size off-by-one:** When setting size or position via expressions or functions, ensure you return numbers, not nil. A mistake like `self:getParent() - 5` instead of `self:getParent():getWidth() - 5` will result in a nil (hence the FAQ example might have a typo) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=element%3AsetPosition%28%22%7Bparent.width%20,5%20end%2C%205)) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=element%3AsetPosition,5%20end%2C%205)). Always use the proper methods (`getParent()` returns the parent element; to get its width, use `:getSize()` or its property).

By anticipating these pitfalls, you can avoid them or quickly solve them. The **FAQ** section on the Basalt documentation is very helpful – it addresses issues like “UI not updating” (call `run()`), “elements not visible” (check bounds/visibility) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F)) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Check%3A)), etc. Consult it whenever something basic seems off.

## Community Insights and Resources

Basalt has an active community of ComputerCraft enthusiasts. Here are some insights and resources gleaned from community forums and discussions:

- **Community projects:** Many community OSes and programs use Basalt for their UI. For inspiration, you can search the ComputerCraft forum or Reddit for “Basalt UI” to find examples of control panels, in-game operating systems, and games made with Basalt. These can provide real-world usage patterns. For instance, one user demonstrated a Redstone control slider built with Basalt (as seen on YouTube) – showing how intuitive it is to tie a Slider’s `onChange` to actual game actions ([Basalt UI Framework Tutorial | CC:Tweaked - YouTube](https://www.youtube.com/watch?v=FlTZxZt_avA#:~:text=Basalt%20UI%20Framework%20Tutorial%20,basalt)).
- **Forum Thread (Author’s Intro):** The original author introduced Basalt saying it can create windows, programs (the Program element), and various controls, aiming to be beginner-friendly yet powerful ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=Basalt%20is%20very%20advanced%20UI,a%20very%20advanced%20operating%20system)). The post emphasizes you can even create “a very advanced operating system” with Basalt ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=window%20which%20executes%20any%20program,a%20very%20advanced%20operating%20system)), which underscores how comprehensive the API is. They also provided an installer command (which has since been updated to the one we used above) ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=Code%20Select%20Expand)). This thread (and subsequent replies) is a good read to understand Basalt’s philosophy and early development.
- **Discord:** Basalt’s Discord server is very helpful for quick questions ([GitHub - Pyroxenium/Basalt: A UI Framework for CC:Tweaked](https://github.com/Pyroxenium/Basalt#:~:text=Check%20out%20the%20wiki%20for,gg%2FyNNnmBVBpE)). The author (NoryiE) and others are often around to answer usage questions or troubleshoot issues. This can be invaluable if you’re stuck, as you can get real-time advice or see frequently asked questions from others.
- **GitHub Issues/Discussions:** The GitHub repo has an *Issues* section and *Discussions* tab ([GitHub - Pyroxenium/Basalt: A UI Framework for CC:Tweaked](https://github.com/Pyroxenium/Basalt#:~:text=,Insights)) ([GitHub - Pyroxenium/Basalt: A UI Framework for CC:Tweaked](https://github.com/Pyroxenium/Basalt#:~:text=Basalt%20is%20intended%20to%20be,and%20you%20may%20find%20bugs)). Scanning those can uncover common requests or problems others have encountered, along with solutions or workarounds. For example, if there was a bug in a certain Basalt version, you might find an issue thread about it. The release notes on GitHub (for v1.7 etc.) list changes – such as the introduction of new objects (Graph, Flexbox, etc.) and improvements ([Release Basalt v1.7 · Pyroxenium/Basalt · GitHub](https://github.com/Pyroxenium/Basalt/releases/tag/v1.7#:~:text=,Reworked%20the%20XML%20System)). Keep an eye on this for updates if you plan to use Basalt long-term.
- **PineStore:** Basalt is available on the CC: Tweaked PineStore (an in-game app store) for easy installation ([Download | Basalt](https://basalt.madefor.cc/guides/download.html#:~:text=Basalt%20is%20available%20in%20two,is%20also%20available%20on%20PineStore)). This indicates it’s recognized as a major library in the CC community.
- **Performance tuning:** A tip from the author – Basalt’s render loop is optimized to only re-draw when needed ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=,elements%20that%20actually%20use%20them)), so spamming `os.queueEvent("someEvent")` won’t cause flicker since Basalt will ignore events that don’t change the UI. However, adding `os.pullEvent("timer")` or heavy logic inside `basalt.run()` (by monkeypatching it) is not advised – use the provided API to schedule or handle custom events. The FAQ also notes that events are only registered for elements that use them, to minimize overhead ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=,elements%20that%20actually%20use%20them)) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=%28timer%20events%20or%20mouse%20events%29,elements%20that%20actually%20use%20them)).
- **Version compatibility:** If you used Basalt 1.6 or earlier, note that 1.7 made significant changes to the object system. The community discussions around May 2023 (when v1.7 released) have advice on migrating (e.g. some method names changed, `Frame` dragging was added, `Animation` became a plugin rather than separate object). Make sure any community code you reference matches the version you have.
- **Learning resources:** In addition to official docs, there are video tutorials (e.g. on YouTube, search “Basalt UI Framework Tutorial”) which walk through building a UI and can help visual learners ([Basalt UI Framework Tutorial | CC:Tweaked - YouTube](https://www.youtube.com/watch?v=FlTZxZt_avA#:~:text=Basalt%20UI%20Framework%20Tutorial%20,basalt)). There’s also an “examples” directory in the Basalt GitHub that has sample programs demonstrating certain widgets; those can be instructive.

Finally, to **train another AI or teach a developer**: The best way to learn is by doing. Encourage experimenting in a live CC:Tweaked environment. Try small snippets for each element to see how they behave. Use the debug tools to inspect what you create. Basalt’s design is quite consistent, so once you grasp how to add an element and set its properties or handle its events, the rest of the API feels natural.

**Summary:** Basalt is a feature-rich GUI toolkit that brings modern UI capabilities to ComputerCraft. Its module functions let you manage frames and the main loop, its suite of UI components cover most interface needs (from basic buttons and labels to complex tables and tree views), and its supplementary systems like state and animation allow you to create dynamic, interactive, and reactive programs. With error handling, logging, and community support, Basalt aims to streamline the process of making polished user interfaces in the CC environment ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=What%20is%20Basalt%3F)). Whether you’re making a simple settings menu or a full-fledged in-game computer OS, Basalt provides the building blocks to do so in a maintainable way. Happy hacking with Basalt!

**References:**

- Basalt Official Documentation (Home, Guides, References) ([Basalt | Basalt](https://basalt.madefor.cc/#:~:text=User%20friendly)) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=What%20is%20Basalt%3F)) ([Frequently Asked Questions | Basalt](https://basalt.madefor.cc/guides/faq.html#:~:text=Why%20isn%27t%20my%20UI%20updating%3F))
- Basalt GitHub Repository and Release Notes ([Release Basalt v1.7 · Pyroxenium/Basalt · GitHub](https://github.com/Pyroxenium/Basalt/releases/tag/v1.7#:~:text=,Reworked%20the%20XML%20System)) ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=Basalt%20is%20now%20able%20to,easeIn%2C%20easeOut%2C%20easeInOut))
- ComputerCraft Forum – Basalt Announcement by NoryiE ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=Basalt%20is%20very%20advanced%20UI,a%20very%20advanced%20operating%20system)) ([Basalt - a new UI Framework](https://forums.computercraft.cc/index.php?topic=433.0#:~:text=Code%20Select%20Expand))
- Reddit /r/ComputerCraft – Basalt update posts and community feedback ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=You%20can%20also%20use%20different,frame)) ([Basalt Update : r/ComputerCraft](https://www.reddit.com/r/ComputerCraft/comments/w81ak4/basalt_update/#:~:text=The%20old%20version%20of%20basalt,side))

--[[
  Basalt API - Comprehensive Guide
  
  Basalt is a powerful UI framework for ComputerCraft that allows you to create
  rich interactive interfaces with minimal effort. This guide will walk you through
  the core concepts and components of Basalt.
  
  Author: Created by GitHub Copilot based on Basalt codebase analysis
]]--

--============================================================================--
-- 1. GETTING STARTED
--============================================================================--

--[[
  First, let's talk about how to include Basalt in your project.
  You can either download it from GitHub or use the ComputerCraft package manager.
]]--

-- Basic setup for a Basalt application:
local basalt = require("basalt")  -- Include the Basalt API

-- Get the main frame (the root container of your application)
local main = basalt.getMainFrame()

-- Add UI elements to the main frame
main:addLabel()
  :setText("Hello, Basalt!")
  :setPosition(2, 2)

-- Start the application
basalt.run()

--[[
  The above code creates a simple application with "Hello, Basalt!" displayed at position (2,2).
  
  Key points:
  1. Every Basalt application starts with creating the main frame
  2. You add UI components to containers (frames)
  3. You must call basalt.run() to start the application
]]--

--============================================================================--
-- 2. CORE CONCEPTS
--============================================================================--

--[[
  Basalt operates on these fundamental concepts:

  1. Element Hierarchy: Elements are organized in a parent-child relationship
  2. Events & Event Handling: UI components respond to user interactions
  3. Properties: Each component has properties that control its appearance and behavior
  4. Method Chaining: Most methods return the element itself for concise coding
  5. State Management: Track and respond to changes in application state
]]--

-- 2.1 Element Hierarchy Example:
local mainFrame = basalt.getMainFrame()
local subFrame = mainFrame:addFrame()
  :setPosition(5, 5)
  :setSize(20, 10)
  :setBackground(colors.lightGray)
  
local button = subFrame:addButton()
  :setText("Click Me")
  :setPosition(2, 2)
  :setSize(10, 3)

--[[
  In this hierarchy:
  - mainFrame is the root container
  - subFrame is a child of mainFrame
  - button is a child of subFrame
]]--

-- 2.2 Event Handling Example:
button:onClick(function()
  -- This function is called when the button is clicked
  subFrame:setBackground(colors.red)
end)

--[[
  Common events include:
  - onClick / onClickUp: Triggered when mouse is clicked/released on an element
  - onScroll: Triggered when scrolling over an element
  - onKey / onChar: Triggered when keyboard input is received (and element is focused)
  - onDrag: Triggered when an element is dragged
  - onFocus / onBlur: Triggered when an element gains/loses focus
]]--

-- 2.3 Properties Example:
button:setBackground(colors.blue)      -- Set background color
button:setForeground(colors.white)     -- Set text color
button:setSize(10, 3)                  -- Set width and height
button:setPosition(2, 2)               -- Set x, y position
button:setZ(5)                         -- Set z-index (rendering order)

local bgColor = button:getBackground() -- Get background color

--============================================================================--
-- 3. UI COMPONENTS
--============================================================================--

--[[
  Basalt provides a rich set of UI components. Here are the most commonly used ones:
]]--

-- 3.1 Labels - For displaying text
local label = main:addLabel()
  :setText("This is a label")
  :setPosition(2, 2)
  :setForeground(colors.yellow)

-- 3.2 Buttons - For user interaction
local button = main:addButton()
  :setText("Click Me")
  :setPosition(2, 4)
  :setSize(10, 3)
  :onClick(function()
    -- Do something when clicked
  end)

-- 3.3 Input Fields - For text entry
local input = main:addInput()
  :setPosition(2, 8)
  :setSize(20, 1)
  :setBackground(colors.white)
  :setForeground(colors.black)
  :setDefaultText("Enter text...")

-- 3.4 Frames - Containers for other elements
local frame = main:addFrame()
  :setPosition(25, 2)
  :setSize(20, 15)
  :setBackground(colors.lightGray)

-- 3.5 Lists - For selecting from multiple options
local list = main:addList()
  :setPosition(2, 10)
  :setSize(15, 5)
  :addItem("Option 1")
  :addItem("Option 2")
  :addItem("Option 3")
  :onChange(function(self, selected)
    -- Do something with selected item
  end)

-- 3.6 Dropdowns - Compact alternative to lists
local dropdown = main:addDropdown()
  :setPosition(2, 16)
  :setSize(15, 1)
  :addItem("Option 1")
  :addItem("Option 2")
  :setSelectedItem("Option 1")

-- 3.7 Checkboxes - For boolean options
local checkbox = main:addCheckbox()
  :setPosition(2, 18)
  :setText("Enable feature")
  :onChange(function(self, checked)
    -- Do something based on checked state
  end)

-- 3.8 Progressbars - For showing progress
local progressbar = main:addProgressbar()
  :setPosition(2, 20)
  :setSize(20, 1)
  :setProgress(50) -- 50%
  :setProgressColor(colors.green)

-- 3.9 Sliders - For selecting a value in a range
local slider = main:addSlider()
  :setPosition(2, 22)
  :setSize(20, 1)
  :setMaxValue(100)
  :setBackgroundSymbol("\140")
  :setSymbol("\149")
  :setValue(25)

-- 3.10 TextBox - Multi-line editable text
local textbox = main:addTextBox()
  :setPosition(25, 20)
  :setSize(30, 10)
  :setText("This is a\nmulti-line\ntextbox")

-- 3.11 Graphs - For data visualization
local lineChart = main:addLineChart()
  :setPosition(50, 2)
  :setSize(25, 10)

-- Add a data series to the chart
lineChart:addSeries("main", " ", colors.red, colors.red)
-- Add points to the series
lineChart:addPoint("main", 5)
lineChart:addPoint("main", 10)
lineChart:addPoint("main", 7)
lineChart:addPoint("main", 12)

-- You can also use bar charts
local barChart = main:addBarChart()
  :setPosition(50, 15)
  :setSize(25, 10)

--============================================================================--
-- 4. LAYOUTS AND POSITIONING
--============================================================================--

--[[
  Basalt provides powerful layout capabilities to organize your UI elements.
]]--

-- 4.1 Absolute Positioning
local button1 = main:addButton()
  :setPosition(5, 5)  -- X: 5, Y: 5
  :setSize(10, 3)
  :setText("Button 1")

-- 4.2 Relative Positioning (using strings)
local frame = main:addFrame()
  :setSize("{parent.width - 10}", "{parent.height - 10}")
  :setPosition(5, 5)

-- 4.3 Flexbox Layout
local flexContainer = main:addFlexbox()
  :setPosition(5, 15)
  :setSize(40, 10)
  :setBackground(colors.lightGray)
  :setFlexDirection("row")  -- "row" or "column"
  :setFlexSpacing(1)
  :setFlexWrap(true)

-- Add items to flexbox
for i = 1, 5 do
  flexContainer:addButton()
    :setText("Item " .. i)
    :setSize(10, 3)
end

-- 4.4 Dynamic Layout Example
-- Functions to get the overall size of all children
local function getChildrenHeight(container)
  local height = 0
  for _, child in ipairs(container.get("children")) do
    if(child.get("visible")) then
      local newHeight = child.get("y") + child.get("height")
      if newHeight > height then
        height = newHeight
      end
    end
  end
  return height
end

-- Creating a scrollable frame
local scrollingFrame = main:addFrame()
  :setSize(20, 10)
  :setPosition(60, 5)
  :setBackground(colors.gray)

scrollingFrame:onScroll(function(self, delta)
  local offset = math.max(0, math.min(
    self.get("offsetY") + delta, 
    getChildrenHeight(self) - self.get("height")
  ))
  self:setOffsetY(offset)
end)

-- Add content to the scrollable frame
for i = 1, 10 do
  scrollingFrame:addButton()
    :setText("Item " .. i)
    :setSize(16, 2)
    :setPosition(2, (i-1)*3 + 2)
end

--============================================================================--
-- 5. STATE MANAGEMENT
--============================================================================--

--[[
  Basalt provides a powerful state management system that lets you:
  1. Define states with initial values
  2. Bind UI elements to states
  3. Create computed states based on other states
  4. React to state changes
]]--

-- 5.1 Basic State Management
local stateFrame = main:addFrame()
  :setPosition(5, 30)
  :setSize(40, 15)
  :setBackground(colors.lightGray)

-- Initialize a state
stateFrame:initializeState("counter", 0)

-- Create a label to display the counter value
local counterLabel = stateFrame:addLabel()
  :setPosition(2, 2)
  :setSize(36, 1)

-- Bind the label text to the counter state
counterLabel:bind("text", function()
  return "Counter: " .. stateFrame:getState("counter")
end)

-- Add buttons to manipulate the state
stateFrame:addButton()
  :setText("+")
  :setPosition(2, 4)
  :setSize(5, 3)
  :onClick(function()
    local current = stateFrame:getState("counter")
    stateFrame:setState("counter", current + 1)
  end)

stateFrame:addButton()
  :setText("-")
  :setPosition(8, 4)
  :setSize(5, 3)
  :onClick(function()
    local current = stateFrame:getState("counter")
    stateFrame:setState("counter", math.max(0, current - 1))
  end)

-- 5.2 Form Validation with Computed States
local formFrame = main:addFrame()
  :setPosition(50, 30)
  :setSize(40, 15)
  :setBackground(colors.lightGray)

-- Initialize form states
formFrame:initializeState("username", "", true) -- true makes it persistent
formFrame:initializeState("password", "", true)

-- Add computed validation state
formFrame:computed("isValid", function(self)
  local username = self:getState("username")
  local password = self:getState("password")
  return #username >= 3 and #password >= 6
end)

-- Create form inputs
formFrame:addLabel()
  :setText("Username:")
  :setPosition(2, 2)

local userInput = formFrame:addInput()
  :setPosition(12, 2)
  :setSize(25, 1)
  :bind("text", "username")  -- Bind input text to username state

formFrame:addLabel()
  :setText("Password:")
  :setPosition(2, 4)

local passInput = formFrame:addInput()
  :setPosition(12, 4)
  :setSize(25, 1)
  :bind("text", "password")  -- Bind input text to password state

-- Status label
local statusLabel = formFrame:addLabel()
  :setPosition(2, 6)
  :setSize(36, 1)

-- React to state changes
formFrame:onStateChange("isValid", function(self, isValid)
  if isValid then
    statusLabel:setText("Form is valid!")
      :setForeground(colors.green)
  else
    statusLabel:setText("Please check your inputs.")
      :setForeground(colors.red)
  end
end)

--============================================================================--
-- 6. ADVANCED FEATURES
--============================================================================--

-- 6.1 Programs - Embed CC programs inside your UI
local programFrame = main:addFrame()
  :setPosition(5, 50)
  :setSize(30, 15)
  :setBackground(colors.black)

local program = programFrame:addProgram()
  :setPosition(1, 1)
  :setSize(30, 15)
  :execute("shell")  -- Run the ComputerCraft shell

-- 6.2 Customizing appearance with themes
basalt.setVariable("theme", {
  ButtonBG = colors.blue,
  ButtonFG = colors.white,
  FrameBG = colors.lightGray,
  FrameFG = colors.black,
  -- Add more theme properties as needed
})

-- 6.3 Animations (using the animation plugin)
local animButton = main:addButton()
  :setPosition(40, 50)
  :setSize(10, 3)
  :setText("Animate")
  :onClick(function(self)
    self:animate({
      property = "background",
      from = colors.blue,
      to = colors.red,
      duration = 1,
      easing = "linear"
    })
  end)

-- 6.4 Custom Plugins
-- Basalt allows the creation of plugins to extend functionality
-- See the official documentation for more details on creating plugins

--============================================================================--
-- 7. DEBUGGING AND PERFORMANCE
--============================================================================--

-- 7.1 Logging
-- You can use the built-in logging functionality
basalt.debug.log("Something happened!")

-- 7.2 Performance Benchmarking
-- Basalt provides tools to measure performance
main:benchmarkContainer("render")  -- Benchmark rendering performance

-- Display benchmark results
main:addButton()
  :setText("Log Benchmarks")
  :setPosition(40, 55)
  :setSize(15, 3)
  :onClick(function()
    main:logContainerBenchmarks("render")
  end)

--============================================================================--
-- 8. BEST PRACTICES
--============================================================================--

--[[
  1. Organize your code into smaller modules
  2. Use constants for colors and positions
  3. Reuse frames and layouts for consistency
  4. Name your UI elements for easier reference
  5. Use computed states to derive values instead of recalculating
  6. Limit the number of elements to improve performance
  7. Use z-index to control rendering order
  8. Take advantage of method chaining for cleaner code
]]--

-- Example of a reusable function to create standard buttons
local function createStandardButton(parent, text, x, y)
  return parent:addButton()
    :setText(text)
    :setPosition(x, y)
    :setSize(10, 3)
    :setBackground(colors.blue)
    :setForeground(colors.white)
end

-- Using the function
local btn1 = createStandardButton(main, "Button 1", 5, 70)
local btn2 = createStandardButton(main, "Button 2", 20, 70)

-- Start your application!
-- basalt.run()  -- Uncomment this line when running the actual program

