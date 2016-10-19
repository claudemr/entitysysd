# EntitySysD

*Component/Entity System* engine written in D. More information may be found on
this [CES wiki](http://entity-systems-wiki.t-machine.org/).

To quote it:
> *Component/Entity Systems are an architectural pattern used mostly in game
development. A CES follows the Composition over Inheritance principle to allow
for greater flexibility when defining entities (anything that's part of a game's
scene: enemies, doors, bullets) by building out of individual parts that can be
mixed-and-matched. This eliminates the ambiguity problems of long inheritance
chains and promotes clean design. However, CES systems do incur a small cost to
performance.*

Nevertheless, we have room to organize components in a cache-friendly manner.


## Usage

### Building

This project uses the DUB build system
(check [here](http://code.dlang.org/download)).

To build the **EntitySysD** library, simply run in the top-level directory
```
dub
```

To use this project as a dependency, add the version you want (see Releases) to
your dub.json:
```
"dependencies": {
    "entitysysd": "~>2.0"
}
```

To build and run all the unit-tests:
```
dub test
```

To generate the documentation, see doc/README.md.


### API documentation

The complete reference API is there (generated with
[ddox](https://github.com/rejectedsoftware/ddox)):
> [Reference API](https://claudemr.github.io/entitysysd/)


### Entities

The `Entity` structure is a simple wrapper around a 64-bit unique id.

Creation of an entity:
```
import entitysysd;

auto ecs = new EntitySysD;

auto entity = ecs.entities.create();
```

Destruction:
```
entity.destroy();
```


### Components

Register a `component` to an entity (the struct is tagged by the `@component`
attribute):
```
@component struct Position
{
    float x, y;
}

auto componentPtr = entity.register!Position(2.0, 3.0);

...

// accessor
entity.component!Position.y += 1.0;
```


### Browsing

Browsing through all valid entities:
```
foreach (entity; ecs.entities)
{
    //do stuff
}
```

Browsing through the instances of a type of component:
```
foreach (componentPtr; ecs.entities.components!Position)
{
    //do stuff
}
```

Browsing through entities with a certain set of components:
```
foreach (entity; ecs.entities.entitiesWith!(Position, Renderable))
{
    //do stuff
}
```

```
foreach (entity, pos, render; ecs.entities.entitiesWith!(Position, Renderable))
{
    // pos is equivalent to entity.component!Position
    // render is equivalent to entity.component!Renderable
}
```

Browsing through the components of an entity.
```
ecs.entities.setAccessor!Position( (e, p) { write("Entity:%s Xpos=%f", entity.toString(), p.x); } );
auto entity = ecs.entities.create();
entity.register!Position(2.0, 3.0);
entity.iterate(); // call accessor delegates of the components registered to entity
```

### Systems

Create a class inheriting from the `System` interface, registering it to the
system manager and running it:

```
class RenderSystem : System
{
    override void run(EntityManager entities, EventManager events, Duration dt)
    {
        // render renderable entities
    }
}

...

ecs.systems.register(new RenderSystem);

...

ecs.systems.run(dur!"msecs"(16));
```


### Events

Subscribing to an event (tagged by the `@event` attribute)

```
@event struct MyEvent
{
    int data;
}

class TestReceiver : Receiver!MyEvent
{
    string str;

    void receive(MyEvent event)
    {
        str ~= event.data.toString;
    }
}

auto evtManager = new EventManager;
evtManager.subscribe!MyEvent(new TestReceiver);

```

Sending events:

```
auto e = MyEvent(43);

evtManager.emit(e);
evtManager.emit!MyEvent(42);
```


## Example

A small application using SDL2 implements **EntitySysD**. It shows some colored
squares bouncing around in a window and exploding when colliding into each
other.

Understanding the code should be pretty straightforward.

Use dub to build and run it:
```
dub --config=example
```

## Thread-safety

**EntitySysD** API is NOT (and will not be) thread-safe. Events will never be
natively sent accross threads. If the user wants to use EntitySysD in a
multi-threaded process, he will have to do its own resource synchronization on
top of it.
Thread-safety adds too much complexity. And from a software architecture point
of view, it makes more sense to manage resource synchronization at the highest
level. **EntitySysD** is just a library.

## Contributors

* [Claude Merle](https://github.com/claudemr)
* [Ryan Roden-Corrent](https://github.com/rcorre)

## Credits

This engine is based on a D port inspired on **EntityX** in C++ of Alec Thomas.
It's been simplified a lot (using D specific features, removing component
handles, etc)):
> https://github.com/alecthomas/entityx/

There are many other CES engines in D out there.

**Star-Entity** is very similar to **EntitySysD** (it is also based upon
EntityX) and I actually came across it after the start of **EntitySysD**
development (had I known about it earlier, and maybe **EntitySysD** would not
have existed at all):
> https://github.com/misu-pwnu/star-entity

**Nitro** design is based on statically built systems and components managers.
There seems to be more thoughts towards cache-efficiency.
> https://github.com/Zoadian/nitro


## Licence

**EntitySysD** is released under the **Lesser-GPL** *v3* licence.
See COPYING.txt and COPYING.LESSER.txt for more information.


## History

### v2.4.x

Changes:
* `ISystem` interface deprecated. Methods added to `System` abstract class
(potentilly an API breaking change, but very unlikely in practise). 
* Allow to register systems in a certain ordering (absolute or relative to an
already registered system). 

Add:
* Statistics added: module `stat`.

### v2.0.x

Change:
* `System` interface is renamed to `ISystem` and becomes an abstract class.
* API break: with `std.meta` and `hasUDA`. It cannot be compiled anymore
with DMD compiler with a version below **2.068.0**.

Add:
* `ISystem` declares 2 new methods: `prepare` and `unprepare`. `System`
abstract class implements empty body for `prepare`, `run` and `unprepare`.
* `SystemManager.runFull` calls `prepare`, `run` and `unprepare`.

To convert 1.x.x user application to 2.0.0, prefix all your `System.run`
methods with `override`, and upgrade your DMD compiler to a version
**>= 2.068.0**.

### v1.x.x

The 1st release puts down the base of **EntitySysD** API.

It uses exceptions (removed all the assert's)

It uses UDA's to tag components and events to ensure the correctness of the
usage of library at compile time.

No benchmarking has been performed. The cache-friendly memory management is
dependant of the application use, and cannot yet be customized for specific
needs at the moment. So the current implementation is pretty naive and could
totally miss the point of being cache-friendly. User experience will tell. So
further enhancements may be programmed.

It has been tested on GNU-Linux environment using DMD64 D Compiler v2.068.x and
v2.069.x.
