/**
Event management module.

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

module entitysysd.event;

import std.algorithm;
import std.container;
import std.typecons;


/// UDA to use upon event struct's and union's.
enum event;

private alias ReceiverDelegate = void delegate(...);

private template isEvent(E)
{
    import std.traits : hasUDA;
    static if(__traits(compiles, hasUDA!(E, event)))
        enum bool isEvent = hasUDA!(E, event) &&
                            (is(E == struct) || is(E == union));
    else
        enum bool isEvent = false;
}


// Used internally by the EventManager.
private struct BaseEventCounter
{
    static size_t counter = 0;
}

private struct EventCounter(Derived)
{
public:
    static size_t getId()
    {
        static size_t counter = -1;
        if (counter == -1)
        {
            counter = mBaseEventCounter.counter;
            mBaseEventCounter.counter++;
        }

        return counter;
    }

private:
    BaseEventCounter mBaseEventCounter;
}


deprecated("Please, use the name `IReceiver` instead.")
alias Receiver = IReceiver;

/**
 * Any receiver class needs to derive from this interface using a specific event
 * type and implement receive.
 */
interface IReceiver(E)
    if (isEvent!E)
{
    /**
     * Will be called each time an event of type E is emitted.
     */
    void receive(E event);
}

///
unittest
{
    @event struct MyEvent
    {
        int data;
    }

    class MySystem : IReceiver!MyEvent
    {
        this(EventManager evtManager)
        {
            evtManager.subscribe!MyEvent(this);
        }

        void receive(MyEvent event)
        {
            import std.stdio : write;
            // do something with event
            write(event.data);
        }
    }
}

/**
 * Manages events and receivers.
 */
class EventManager
{
public:
    /**
     * Check whether a receiver class is subscribed to an event.
     * Returns: true if it is subscribed, false otherwise.
     */
    bool isSubscribed(E)(IReceiver!E receiver)
        if (isEvent!E)
    {
        auto receive = cast(ReceiverDelegate)&receiver.receive;
        auto eventId = EventCounter!E.getId();
        auto handlerGroup = eventId in mHandlers;

        if (handlerGroup is null)
            return false;

        if ((*handlerGroup).find(receive).length == 0)
            return false;

        return true;
    }

    /**
     * Subscribe a receiver class instance to an event.
     */
    void subscribe(E)(IReceiver!E receiver)
        if (isEvent!E)
    {
        auto receive = cast(ReceiverDelegate)&receiver.receive;
        auto eventId = EventCounter!E.getId();
        auto handlerGroup = eventId in mHandlers;

        // no subscriber for the event family, so create one, and we're done
        if (handlerGroup is null)
        {
            mHandlers[eventId] = [];
            mHandlers[eventId] ~= receive;
            return;
        }

        // already subscribed?
        if ((*handlerGroup).find(receive).length != 0)
            return;

        // look for empty spots
        foreach (ref rcv; *handlerGroup)
            if (rcv is null)
            {
                rcv = receive;
                return;
            }

        // else append the subscriber callback to the array
        *handlerGroup ~= receive;
    }

    /**
     * Unsubscribe a receiver class instance from an event.
     */
    void unsubscribe(E)(IReceiver!E receiver)
        if (isEvent!E)
    {
        auto receive = cast(ReceiverDelegate)&receiver.receive;
        auto eventId = EventCounter!E.getId();
        auto handlerGroup = eventId in mHandlers;

        if (handlerGroup is null)
            return;

        foreach (ref rcv; *handlerGroup)
            if (rcv == receive)
            {
                rcv = null;
                return; // there should be only one occurence of receive
            }
    }

    /**
     * Emit an event.
     *
     * It will be dispatched to all receivers that subscribed to it.
     */
    void emit(E)(in ref E event)
        if (isEvent!E)
    {
        auto eventId = EventCounter!E.getId();
        auto handlerGroup = eventId in mHandlers;

        if (handlerGroup is null) // no event-receiver registered yet
            return;

        foreach (rcv; *handlerGroup)
        {
            // already subscribed
            if (rcv !is null)
            {
                auto rcvE = cast(void delegate(in E))rcv;
                rcvE(event);
            }
        }
    }

    /** ditto */
    void emit(E, Args...)(auto ref Args args)
        if (isEvent!E)
    {
        auto event = E(args);
        emit(event);
    }

    ///
    unittest
    {
        @event struct MyEvent
        {
            int data;
        }

        auto em = new EventManager;

        auto e = MyEvent(43);

        em.emit(e);
        em.emit!MyEvent(42);
    }

private:

    // For each id of event, we have a list of receiver-delegates
    ReceiverDelegate[][size_t] mHandlers;
}


//******************************************************************************
//***** UNIT-TESTS
//******************************************************************************

version(unittest)
{

import std.conv;
import std.stdio;

@event struct TestEvent
{
    string data;
}

@event struct IntEvent
{
    int data;
}

class TestReceiver0 : IReceiver!TestEvent
{
    string str;

    this(EventManager evtManager)
    {
        evtManager.subscribe!TestEvent(this);
    }

    void receive(TestEvent event)
    {
        str ~= event.data;
    }
}

class TestReceiver1 : IReceiver!IntEvent
{
    string str;

    this(EventManager evtManager)
    {
        evtManager.subscribe!IntEvent(this);
        // do it aagain, it should silently return without subscribing it
        // a second time
        evtManager.subscribe!IntEvent(this);
    }

    void receive(IntEvent event)
    {
        str ~= to!string(event.data);
    }
}

class TestReceiver2 : IReceiver!TestEvent, IReceiver!IntEvent
{
    string str;

    this(EventManager evtManager)
    {
        evtManager.subscribe!TestEvent(this);
        assert(evtManager.isSubscribed!TestEvent(this));
        assert(!evtManager.isSubscribed!IntEvent(this));
        evtManager.subscribe!IntEvent(this);
    }

    void receive(TestEvent event)
    {
        str ~= event.data;
    }
    void receive(IntEvent event)
    {
        str ~= event.data.to!(string)();
    }
}

}

unittest
{
    auto strEvt0 = TestEvent("hello");
    auto strEvt1 = TestEvent("world");
    auto intEvt0 = IntEvent(123);
    auto intEvt1 = IntEvent(456);

    //*** create a new event manager ***
    auto evtManager = new EventManager;

    //*** test with one receiver ***
    auto testRcv0 = new TestReceiver0(evtManager);

    evtManager.emit!(TestEvent)("goodbye ");
    evtManager.emit(strEvt1);

    assert(testRcv0.str == "goodbye world");

    //*** test with multiple receiver and multiple events ***
    auto testRcv1 = new TestReceiver1(evtManager);
    auto testRcv2 = new TestReceiver2(evtManager);
    testRcv0.str = ""; // reset string

    evtManager.emit(intEvt0);
    evtManager.emit(strEvt1);
    evtManager.emit(strEvt0);
    evtManager.emit(intEvt1);
    evtManager.emit(strEvt0);
    evtManager.emit(intEvt0);
    evtManager.emit(intEvt1);

    assert(testRcv0.str == "worldhellohello");
    assert(testRcv1.str == "123456123456");
    assert(testRcv2.str == "123worldhello456hello123456");

    //*** test unsubscribe ***
    evtManager.unsubscribe!TestEvent(testRcv2);
    testRcv0.str = ""; // reset string
    testRcv1.str = ""; // reset string
    testRcv2.str = ""; // reset string

    evtManager.emit(intEvt0);
    evtManager.emit(strEvt0);

    assert(testRcv0.str == "hello");
    assert(testRcv1.str == "123");
    assert(testRcv2.str == "123");

    evtManager.unsubscribe!TestEvent(testRcv0);
    evtManager.unsubscribe!IntEvent(testRcv2);
    evtManager.subscribe!TestEvent(testRcv2);

    evtManager.emit(strEvt1);
    evtManager.emit(intEvt1);

    assert(testRcv0.str == "hello");
    assert(testRcv1.str == "123456");
    assert(testRcv2.str == "123world");
}

// validate that sending an event with no registered receivers does not crash
unittest
{
    auto evtManager = new EventManager;

    // registers a handler for StringEvent, but not IntEvent
    auto testRcv0 = new TestReceiver0(evtManager);

    // a bug caused this to fail when at least 1 receiver was registered but
    // no receivers were registered for this event type
    evtManager.emit!IntEvent(123);
}
