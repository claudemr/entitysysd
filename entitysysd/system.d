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

import entitysysd.entity;
import entitysysd.event;
import entitysysd.exception;

public import core.time;
import std.algorithm;
import std.container;
import std.range;
import std.typecons;


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
     * If `flag` is `Yes.AutoSubscribe` (default), this will automatically
     * subscribe `system` to any events for which it implements `Receiver`.
     * Note that this will not work if `system` is passed as `ISystem` -- it
     * should be passed as its full type.
     *
     * Throws: SystemException if the system was already registered.
     */
    void register(T : ISystem)(T system,
                               Flag!"AutoSubscribe" flag = Yes.AutoSubscribe)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(sysNode.empty);
        mSystems ~= system;

        // auto-subscribe to events
        if (flag)
        {
            import std.traits : InterfacesTuple;
            foreach(Interface ; InterfacesTuple!T)
            {
                static if (is(Interface : IReceiver!E, E))
                    mEventManager.subscribe!E(system);
            }
        }
    }

    /**
     * Unregister a system.
     *
     * If `flag` is `Yes.AutoSubscribe` (default), this will automatically
     * unsubscribe `system` from any events for which it implements `Receiver`.
     * Note that this will not work if `system` is passed as `ISystem` -- it
     * should be passed as its full type.
     *
     * Throws: SystemException if the system was not registered.
     */
    void unregister(T : ISystem)(T system,
                                 Flag!"AutoSubscribe" flag = Yes.AutoSubscribe)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(!sysNode.empty);
        mSystems.linearRemove(sysNode.take(1));

        // auto-unsubscribe from events
        if (flag)
        {
            import std.traits : InterfacesTuple;
            foreach(Interface ; InterfacesTuple!T)
            {
                static if (is(Interface : Receiver!E, E))
                    mEventManager.unsubscribe!E(system);
            }
        }
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

    // todo opApply to browse through systems
    // todo Reorder systems with priorities. Can be absolute (signed integer)
    //      with special values such as "top", or "bottom". Can be relative to
    //      an already registered system "Above", "Behind".
    // todo Statistics module, allow to measure time consumed by a system.
    //      Measure the whole (runFull) loop, measure only run's of every
    //      systems and measure each individual system's run (skip prepare and
    //      unprepare which should never hold big processing routines).
    //      So SystemManager has 2 Stat instances, and each System may have 1
    //      that can be turned on/off.
    //      Stat interface provides an updateRate property, which will give a
    //      period of time where the delay's will be sum to get an average, min
    //      and max. A delegate may be given to be called-back when it updates.

private:
    EntityManager   mEntityManager;
    EventManager    mEventManager;
    DList!ISystem   mSystems;
}


// validate event auto-subscription/unsubscription
unittest
{
    @event struct EventA
    {
    }

    @event struct EventB
    {
    }

    class MySys : System, Receiver!EventA, Receiver!EventB
    {
        int eventCount;
        void receive(EventA ev)
        {
            ++eventCount;
        }
        void receive(EventB ev)
        {
            ++eventCount;
        }
    }

    auto events = new EventManager;
    auto entities = new EntityManager(events);
    auto systems = new SystemManager(entities, events);

    auto sys = new MySys;

    // regsitering the system should subscribe to MyEvent
    systems.register(sys);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 2);

    // regsitering the system should unsubscribe from MyEvent
    systems.unregister(sys);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 2);

    // explicitly disallow auto-subscription
    systems.register(sys, No.AutoSubscribe);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 2);

    //// unregister without unsubscribing
    systems.unregister(sys);
    systems.register(sys, Yes.AutoSubscribe);
    systems.unregister(sys, No.AutoSubscribe);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 4);
}
