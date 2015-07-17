EntitySysD
==========

D Entity/Component System engine.

History
-------

It is a D port inspired on EntityX in C++ from Alec Thomas.
> https://github.com/alecthomas/entityx/

It has been adapted to be integrated first into a 3D FPS-like game written
in D.

It implements the idea of having entities enumerated by a unique id.
Components may be attached to those entities, and system are pieces of code that
applies to some sets of components from various entities. In EntitySysD,
components are arranged in memory, in order to avoid any cache-miss while
broaing though a same family of components.

It is released under the Lesser-GPL v3 licence.

Example
-------

A small application using SDL2 implements EntitySysD. It shows some colored
squares bouncing around in a window and exploding when colliding into each
other.

Understanding the code should be pretty straightforward.

Use dub to build it:
> dub --config=example

Versions
--------

The current initial version does not implement component-dependencies.

It lacks some proper debugging toward resource destruction (it relies on the D
garbage collector, which might not be efficient enough for game purposes).

It lacks a proper API documentation (use ddoc).

No benchmarking has been performed. The cache-friendly memory management is
dependant of the application use, and cannot yet be customized for specific
needs at the moment. So the current implementation is pretty naive and could
totally miss the point of being cache-friendly. User experience will tell. So
further enhancements may be programmed.

This current version (Major 0) may be subject to API changes (though the general
philosophy will not change). Once the API is properly defined and documented,
EntitySysD will move towards Major version 1 (and so forth).
> http://semver.org/

It has been tested on GNU-Linux environment using DMD64 D Compiler v2.067.1.