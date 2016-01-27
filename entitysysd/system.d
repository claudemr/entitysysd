/**
System management module.

Copyright: © 2015-2016 Claude Merle
Authors: Claude Merle
License: This file is part of EntitySysD.

EntitySysD is free software: you can redistribute it and/or modify it
under the terms of the Lesser GNU General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EntitySysD is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
Lesser GNU General Public License for more details.

You should have received a copy of the Lesser GNU General Public License
along with EntitySysD. If not, see $(LINK http://www.gnu.org/licenses/).
*/

module entitysysd.system;

public import core.time;
import std.algorithm;
import std.container;
import std.range;

import entitysysd.entity;
import entitysysd.event;
import entitysysd.exception;


/**
 * ISystem interface. System classes must derive from it and implement
 * $(D prepare), $(D run) or $(D unprepare).
 */
interface ISystem
{
    /**
     * Prepare any data for the frame before a proper run.
     */
    void prepare(EntityManager entities, EventManager events, Duration dt);

    /**
     * Called by the system-manager anytime its method run is called.
     */
    void run(EntityManager entities, EventManager events, Duration dt);

    /**
     * Unprepare any data for the frame after the run.
     */
    void unprepare(EntityManager entities, EventManager events, Duration dt);
}


/**
 * System abstract class. System classes may derive from it and override
 * $(D prepare), $(D run) or $(D unprepare).
 */
abstract class System : ISystem
{
    /**
     * Prepare any data for the frame before a proper run.
     */
    void prepare(EntityManager entities, EventManager events, Duration dt)
    {
    }

    /**
     * Called by the system-manager anytime its method run is called.
     */
    void run(EntityManager entities, EventManager events, Duration dt)
    {
    }

    /**
     * Unprepare any data for the frame after the run.
     */
    void unprepare(EntityManager entities, EventManager events, Duration dt)
    {
    }
}


/**
 * Entry point for systems. Allow to register systems.
 */
class SystemManager
{
public:
    this(EntityManager entityManager,
         EventManager  eventManager)
    {
        mEntityManager = entityManager;
        mEventManager  = eventManager;
    }

    /**
     * Register a new system.
     *
     * Throws: SystemException if the system was already registered.
     */
    void register(ISystem system)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(sysNode.empty);
        mSystems ~= system;
    }

    /**
     * Unregister a system.
     *
     * Throws: SystemException if the system was not registered.
     */
    void unregister(ISystem system)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(!sysNode.empty);
        mSystems.linearRemove(sysNode.take(1));
    }

    /**
     * Prepare all the registered systems.
     *
     * They are prepared in the order that they were registered.
     */
    void prepare(Duration dt)
    {
        foreach (s; mSystems)
            s.prepare(mEntityManager, mEventManager, dt);
    }

    /**
     * Run all the registered systems.
     *
     * They are runt in the order that they were registered.
     */
    void run(Duration dt)
    {
        foreach (s; mSystems)
            s.run(mEntityManager, mEventManager, dt);
    }

    /**
     * Unprepare all the registered systems.
     *
     * They are unprepared in the reverse order that they were registered.
     */
    void unprepare(Duration dt)
    {
        foreach_reverse (s; mSystems)
            s.unprepare(mEntityManager, mEventManager, dt);
    }

    /**
     * Prepare, run and unprepare all the registered systems.
     */
    void runFull(Duration dt)
    {
        prepare(dt);
        run(dt);
        unprepare(dt);
    }

private:
    EntityManager   mEntityManager;
    EventManager    mEventManager;
    DList!ISystem   mSystems;
}
