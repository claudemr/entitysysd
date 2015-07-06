module entitysysd.event;


private alias ReceiverDelegate = void delegate(BaseEvent);


// Used internally by the EventManager.
class BaseEvent
{
public:
    alias Family = size_t;

protected:
    static Family mFamilyCounter = 0;
};


/**
 * Event types should subclass from this.
 *
 * struct Explosion : public Event<Explosion> {
 *   Explosion(int damage) : damage(damage) {}
 *   int damage;
 * };
 */
class Event(Derived) : BaseEvent
{
public:
    /// Create a family id for each derived event
    static Family family()
    {
        static Family family = -1;
        if (family == -1)
        {
            family = mFamilyCounter;
            mFamilyCounter++;
        }

        return family;
    }
};


class BaseReceiver
{
public:
    ~this()
    {
        foreach (connection; mConnections)
        {
           /*auto &ptr = connection.second.first;
           if (!ptr.expired())
               ptr.lock()->disconnect(connection.second.second);*/
        }
    }

    // Return number of signals connected to this receiver.
    size_t nbConnection()
    {
        return mConnections.length;
    }

    void connect(ReceiverDelegate *pReceive)
    {
        foreach (pRcv; mConnections)
            // already subscribed
            if (*pRcv == *pReceive)
                return;

        mConnections ~= pReceive;
    }

    void disconnect(ReceiverDelegate *pReceive)
    {
        foreach (pRcv; mConnections)
            // already subscribed
            if (*pRcv == *pReceive)
                pRcv = null;
    }

private:
    //std::unordered_map<BaseEvent::Family, std::pair<EventSignalWeakPtr, std::size_t>> mConnections;
    ReceiverDelegate*[] mConnections;
};


class Receiver(Derived) : BaseReceiver
{
};


/**
 * Handles event subscription and delivery.
 *
 * Subscriptions are automatically removed when receivers are destroyed..
 */
class EventManager
{
public:
    /**
     * Subscribe an object to receive events of type E.
     *
     * Receivers must be subclasses of Receiver and must implement a receive() method accepting the given event type.
     *
     * eg.
     *
     *     struct ExplosionReceiver : public Receiver<ExplosionReceiver> {
     *       void receive(const Explosion &explosion) {
     *       }
     *     };
     *
     *     ExplosionReceiver receiver;
     *     em.subscribe<Explosion>(receiver);
     */
    void subscribe(E, R)(R receiver)
    {
        ReceiverDelegate receive = cast(ReceiverDelegate)&receiver.receive;
        auto eventFamily = E.family();

        if (!(eventFamily in mHandlers))
            mHandlers[eventFamily] = [];

        mHandlers[eventFamily] ~= receive;
        receiver.connect(&mHandlers[eventFamily][$-1]);
    }

    /**
     * Unsubscribe an object in order to not receive events of type E anymore.
     *
     * Receivers must have subscribed for event E before unsubscribing from event E.
     *
     */
    void unsubscribe(E, Receiver)(Receiver receiver)
    {
        ReceiverDelegate receive = &receiver.receive;
        auto eventFamily = E.family();

        if (!(eventFamily in mHandlers))
            return;

        foreach (ref rcv; mHandlers[eventFamily])
            rcv = null;

        foreach (ref rcv; mHandlers.data[eventFamily])
            // already subscribed
            if (rcv == receive)
            {
                receiver.disconnect(&rcv);
                rcv = null;
            }
    }

    /**
     * Emit an already constructed event.
     */
    void emit(E)(E event)
    {
        auto eventFamily = E.family();

        foreach (rcv; mHandlers[eventFamily])
            // already subscribed
            if (rcv !is null)
                rcv(event);
    }

    /**
     * Emit an event to receivers.
     *
     * This method constructs a new event object of type E with the provided arguments, then delivers it to all receivers.
     *
     * eg.
     *
     * auto em = new EventManager();
     * em.emit!(Explosion)(10);
     *
     */
    void emit(E, Args...)(Args args)
    {
        auto event = new E(args);
        emit(event);
    }

    size_t nbConnectedReceivers()
    {
        return mHandlers.length;
    }

private:

    // For each family of event, we have a set of receiver-delegates
    ReceiverDelegate[][BaseEvent.Family] mHandlers;
}


import std.conv;
import std.stdio;

unittest
{
    //dmd -main -unittest entitysysd/event.d
    static class TestEvent : Event!(TestEvent)
    {
        this(string str)
        {
            data = str.idup;
        }

        string data;
    }

    static class IntEvent : Event!(IntEvent)
    {
        this(int n)
        {
            data = n;
        }

        int data;
    }

    auto strEvt0 = new TestEvent("hello");
    auto strEvt1 = new TestEvent("world");
    auto intEvt0 = new IntEvent(123);
    auto intEvt1 = new IntEvent(456);

    //*** Check event family works fine ***
    assert(strEvt0.family == 0);
    assert(intEvt1.family == 1);
    assert(strEvt0.family == 0);
    assert(strEvt1.family == 0);
    assert(intEvt0.family == 1);
    assert(intEvt1.family == 1);

    static class TestReceiver0 : Receiver!(TestReceiver0)
    {
        string str;

        this(EventManager evtManager)
        {
            evtManager.subscribe!(TestEvent)(this);
        }

        void receive(TestEvent event)
        {
            str ~= event.data;
        }
    }

    //*** create a new event manager ***
    auto evtManager = new EventManager;

    //*** test with one receiver ***
    auto testRcv0 = new TestReceiver0(evtManager);

    evtManager.emit!(TestEvent)("goodbye ");
    evtManager.emit(strEvt1);

    assert(testRcv0.str == "goodbye world");

    //*** test with multiple receiver and multiple events ***
    static class TestReceiver1 : Receiver!(TestReceiver1)
    {
        string str;

        this(EventManager evtManager)
        {
            evtManager.subscribe!(IntEvent)(this);
        }

        void receive(IntEvent event)
        {
            str ~= event.data.to!(string)();
        }
    }

    static class TestReceiver2 : Receiver!(TestReceiver2)
    {
        string str;

        this(EventManager evtManager)
        {
            evtManager.subscribe!(TestEvent)(this);
            evtManager.subscribe!(IntEvent)(this);
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

    auto testRcv1 = new TestReceiver1(evtManager);
    auto testRcv2 = new TestReceiver2(evtManager);
    testRcv0.str = ""; // reset string

    /*evtManager.emit(intEvt0);
    evtManager.emit(strEvt1);
    evtManager.emit(strEvt0);
    evtManager.emit(intEvt1);
    evtManager.emit(strEvt0);
    evtManager.emit(intEvt0);
    evtManager.emit(intEvt1);

    assert(testRcv2.str == "123worldhello456hello123456");*/
}
