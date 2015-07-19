/*
Copyright 2015 Claude Merle

This file is part of EntitySysD.

EntitySysD is free software: you can redistribute it and/or modify it
under the terms of the Lesser GNU General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EntitySysD is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
Lesser GNU General Public License for more details.

You should have received a copy of the Lesser GNU General Public License
along with EntitySysD. If not, see <http://www.gnu.org/licenses/>.
*/

module entitysysd.event;
import std.typecons;


enum event;

private alias ReceiverDelegate = void delegate(...);

private template isEvent(E)
{
    import std.typetuple : anySatisfy;
    enum isEventAttr(D) = is(D == event);
    static if(__traits(compiles, __traits(getAttributes, E)))
        enum isEvent = (anySatisfy!(isEventAttr,
                        __traits(getAttributes, E)));
    else
        enum isEvent = false;
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


interface Receiver(E)
{
    void receive(E event);
}


class EventManager
{
public:
    void subscribe(E)(Receiver!E receiver)
        if (isEvent!E)
    {
        ReceiverDelegate receive = cast(ReceiverDelegate)&receiver.receive;
        auto eventId = EventCounter!E.getId();

        // no subscriber for the event family, so create one, and we're done
        if (!(eventId in mHandlers))
        {
            mHandlers[eventId] = [];
            mHandlers[eventId] ~= receive;
            return;
        }

        // already subscribed?
        foreach (ref rcv; mHandlers[eventId])
            assert(!(rcv == receive));

        // look for empty spots
        foreach (ref rcv; mHandlers[eventId])
            if (rcv is null)
            {
                rcv = receive;
                return;
            }

        // else append the subscriber callback to the array
        mHandlers[eventId] ~= receive;
    }


    void unsubscribe(E)(Receiver!E receiver)
        if (isEvent!E)
    {
        ReceiverDelegate receive = cast(ReceiverDelegate)&receiver.receive;
        auto eventId = EventCounter!E.getId();

        assert(eventId in mHandlers);

        foreach (ref rcv; mHandlers[eventId])
            if (rcv == receive)
                rcv = null;
    }

    void emit(E)(in ref E event)
        if (isEvent!E)
    {
        auto eventId = EventCounter!E.getId();

        foreach (rcv; mHandlers[eventId])
        {
            // already subscribed
            if (rcv !is null)
            {
                auto rcvE = cast(void delegate(in E))rcv;
                rcvE(event);
            }
        }
    }

    void emit(E, Args...)(auto ref Args args)
        if (isEvent!E)
    {
        auto event = E(args);
        emit(event);
    }

private:

    // For each id of event, we have a set of receiver-delegates
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

class TestReceiver0 : Receiver!TestEvent
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

class TestReceiver1 : Receiver!IntEvent
{
    string str;

    this(EventManager evtManager)
    {
        evtManager.subscribe!IntEvent(this);
    }

    void receive(IntEvent event)
    {
        str ~= to!string(event.data);
    }
}

class TestReceiver2 : Receiver!TestEvent, Receiver!IntEvent
{
    string str;

    this(EventManager evtManager)
    {
        evtManager.subscribe!TestEvent(this);
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
