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

public import entitysysd.stat;

import entitysysd.entity;
import entitysysd.event;
import entitysysd.exception;
import std.algorithm;
import std.container;
import std.format;
import std.range;
import std.typecons;


/**
 * Enum allowing to give special order of a system when registering it to the
 * $(D SystemManager).
 */
struct Order
{
public:
    /// Fisrt place in the list.
    static auto first() @property
    {
        return Order(true, null);
    }
    /// Last place in the list.
    static auto last() @property
    {
        return Order(false, null);
    }
    /// Place before $(D system) in the list.
    static auto before(S : System)(S system)
    {
        return Order(true, cast(System)system);
    }
    /// Place after $(D system) in the list.
    static auto after(S : System)(S system)
    {
        return Order(false, cast(System)system);
    }

private:
    bool   mIsFirstOrBefore;
    System mSystem;
}

/**
 * Deprecated. Alias to keep relative backward compatibility with older
 * interface.
 */
deprecated("Please, use the abstract class `System` instead.")
alias ISystem = System;

/**
 * System abstract class. System classes may derive from it and override
 * $(D prepare), $(D run) or $(D unprepare).
 */
abstract class System
{
protected:
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

public:
    /**
     * Change ordering of the system in the system-manager list.
     *
     * Throw:
     * - A $(D SystemException) if the system is not registered.
     */
    final void reorder(Order order)
    {
        enforce!SystemException(mManager !is null);

        auto sr = mManager.mSystems[].find(this);
        enforce!SystemException(!sr.empty);

        mManager.mSystems.linearRemove(sr.take(1));

        mManager.insert(this, order);
    }

    /**
     * Name of system (given once at the registration by the system-manager).
     */
    final string name() @property const
    {
        return mName;
    }

    /**
     * Reference on the system statistics.
     */
    final ref const(Stat) stat() @property const
    {
        return mStat;
    }

private:
    string        mName;
    SystemManager mManager;
    Stat          mStat;
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
     * Note that this will not work if `system` is passed as `System` -- it
     * should be passed as its full type.
     *
     * Throws: SystemException if the system was already registered.
     */
    void register(S : System)
                 (S system,
                  Order order = Order.last,
                  Flag!"AutoSubscribe" flag = Yes.AutoSubscribe)
    {
        // Check system is not already registered
        auto sr = mSystems[].find(system);
        enforce!SystemException(sr.empty);

        insert(system, order);

        auto s = cast(System)system;
        s.mName = S.stringof ~ format("@%04x", cast(ushort)cast(void*)system);
        s.mManager = this;

        // auto-subscribe to events
        if (flag)
        {
            import std.traits : InterfacesTuple;
            foreach (Interface ; InterfacesTuple!S)
            {
                static if (is(Interface : IReceiver!E, E))
                    mEventManager.subscribe!E(system);
            }
        }
    }

    /// ditto
    void register(S : System)
                 (S system, Flag!"AutoSubscribe" flag)
    {
        register(system, Order.last, flag);
    }

    /**
     * Unregister a system.
     *
     * If `flag` is `Yes.AutoSubscribe` (default), this will automatically
     * unsubscribe `system` from any events for which it implements `Receiver`.
     * Note that this will not work if `system` is passed as `System` -- it
     * should be passed as its full type.
     *
     * Throws: SystemException if the system was not registered.
     */
    void unregister(S : System)(S system,
                                Flag!"AutoSubscribe" flag = Yes.AutoSubscribe)
    {
        auto sr = mSystems[].find(system);
        enforce!SystemException(!sr.empty);

        mSystems.linearRemove(sr.take(1));

        auto s = cast(System)system;
        s.mManager = null;

        // auto-unsubscribe from events
        if (flag)
        {
            import std.traits : InterfacesTuple;
            foreach (Interface ; InterfacesTuple!S)
            {
                static if (is(Interface : IReceiver!E, E))
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
        if (mStatEnabled)
            mStatRun.start();

        foreach (sys; mSystems)
        {
            if (mStatEnabled)
                sys.mStat.start();
            sys.run(mEntityManager, mEventManager, dt);
            if (mStatEnabled)
                sys.mStat.stop();
        }

        if (mStatEnabled)
            mStatRun.stop();
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
        if (mStatEnabled)
            mStatAll.start();

        prepare(dt);
        run(dt);
        unprepare(dt);

        if (mStatEnabled)
        {
            mStatAll.stop();

            if (mStatAll.elapsedTime >= mStatRate)
            {
                mStatRun.update();
                mStatAll.update();
                foreach (sys; mSystems)
                    sys.mStat.update();

                if (mStatDg !is null)
                    mStatDg();
            }
        }
    }


    /**
     * Return a bidirectional range on the list of the registered systems.
     */
    auto opSlice()
    {
        return mSystems[];
    }

    /**
     * Reference on profiling statistics of all the system's run.
     */
    final ref const(Stat) statRun() @property const
    {
        return mStatRun;
    }

    /**
     * Reference on profiling statistics of all the system's prepare, unprepare
     * and run.
     */
    final ref const(Stat) statAll() @property const
    {
        return mStatAll;
    }

    /**
     * Enable statistics profiling on the system-manager and all its
     * registered systems.
     * A delegate $(D dg) can be given, the $(D rate) at which it will be called
     * to provide significant stat's.
     */
    void enableStat(Duration rate = seconds(0), void delegate() dg = null)
    {
        mStatEnabled = true;
        mStatRate    = rate;
        mStatDg      = dg;
    }

    /**
     * Disable statistics profiling on the system-manager and all its
     * registered systems.
     */
    void disableStat()
    {
        mStatEnabled = false;
        mStatRun.clear();
        mStatAll.clear();
        foreach (sys; mSystems)
            sys.mStat.clear();
    }

    /**
     * Tells whether statistics profiling is enabled or not.
     */
    bool statEnabled() @property const
    {
        return mStatEnabled;
    }

private:
    void insert(System system, Order order)
    {
        if (order == Order.first)
        {
            mSystems.insertFront(cast(System)system);
        }
        else if (order == Order.last)
        {
            mSystems.insertBack(cast(System)system);
        }
        else if (order.mIsFirstOrBefore)
        {
            auto or = mSystems[].find(order.mSystem);
            enforce!SystemException(!or.empty);
            mSystems.insertBefore(or, cast(System)system);
        }
        else //if (!order.mIsFirstOrBefore)
        {
            auto or = mSystems[];
            enforce!SystemException(!or.empty);
            //xxx dodgy, but DList's are tricky
            while (or.back != order.mSystem)
            {
                or.popBack();
                enforce!SystemException(!or.empty);
            }
            mSystems.insertAfter(or, cast(System)system);
        }
    }

    EntityManager   mEntityManager;
    EventManager    mEventManager;
    DList!System    mSystems;
    bool            mStatEnabled;
    Duration        mStatRate;
    void delegate() mStatDg;
    Stat            mStatAll;
    Stat            mStatRun;
}


//******************************************************************************
//***** UNIT-TESTS
//******************************************************************************

// validate event auto-subscription/unsubscription
unittest
{
    @event struct EventA
    {
    }

    @event struct EventB
    {
    }

    class MySys : System, IReceiver!EventA, IReceiver!EventB
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

    // registering the system should subscribe to MyEvent
    systems.register(sys);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 2);

    // registering the system should unsubscribe from MyEvent
    systems.unregister(sys);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 2);

    // explicitly disallow auto-subscription
    systems.register(sys, Order.last, No.AutoSubscribe);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 2);

    // unregister without unsubscribing
    systems.unregister(sys);
    systems.register(sys, Yes.AutoSubscribe);
    systems.unregister(sys, No.AutoSubscribe);
    events.emit!EventA();
    events.emit!EventB();
    assert(sys.eventCount == 4);
}


// validate ordering
unittest
{
    class MySys0 : System
    {
    }

    class MySys1 : System
    {
    }

    auto events = new EventManager;
    auto entities = new EntityManager(events);
    auto systems = new SystemManager(entities, events);

    auto sys0 = new MySys0;
    auto sys1 = new MySys1;
    auto sys2 = new MySys0;
    auto sys3 = new MySys1;
    auto sys4 = new MySys0;
    auto sys5 = new MySys1;
    auto sys6 = new MySys0;
    auto sys7 = new MySys1;

    // registering the systems
    systems.register(sys0);
    systems.register(sys1, Order.last);
    systems.register(sys2, Order.first);
    systems.register(sys3, Order.first);
    systems.register(sys4, Order.after(sys2));
    systems.register(sys5, Order.before(sys3));
    systems.register(sys6, Order.after(sys1));
    systems.register(sys7, Order.before(sys4));

    // check order is correct
    auto sysRange = systems[];
    assert(sysRange.front == sys5);
    sysRange.popFront();
    assert(sysRange.front == sys3);
    sysRange.popFront();
    assert(sysRange.front == sys2);
    sysRange.popFront();
    assert(sysRange.front == sys7);
    sysRange.popFront();
    assert(sysRange.front == sys4);
    sysRange.popFront();
    assert(sysRange.front == sys0);
    sysRange.popFront();
    assert(sysRange.front == sys1);
    sysRange.popFront();
    assert(sysRange.front == sys6);
    sysRange.popFront();
    assert(sysRange.empty);

    // check re-ordering works
    sys3.reorder(Order.first);

    sysRange = systems[];
    assert(sysRange.front == sys3);
    sysRange.popFront();
    assert(sysRange.front == sys5);
    sysRange.popFront();
    assert(sysRange.front == sys2);
    sysRange.popFront();
    assert(!sysRange.empty);

    // check exceptions
    auto sysNA = new MySys0;
    auto sysNB = new MySys1;

    assert(collectException!SystemException(
            systems.register(sys1))
            !is null);
    assert(collectException!SystemException(
            systems.unregister(sysNA))
            !is null);
    assert(collectException!SystemException(
            systems.register(sysNA, Order.after(sysNB)))
            !is null);
    assert(collectException!SystemException(
            systems.register(sysNA, Order.before(sysNB)))
            !is null);
}