module entitysysd.event;

import std.array;

alias EventSignal = void*;//Simple::Signal<void (const void*)>;
alias EventSignalPtr = void*;//std::shared_ptr<EventSignal>;
alias EventSignalWeakPtr = void*;//std::weak_ptr<EventSignal>;

/// Used internally by the EventManager.
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
    size_t nbConnectedSignals()
    {
        return mConnections.length;
    }

private:
    //std::unordered_map<BaseEvent::Family, std::pair<EventSignalWeakPtr, std::size_t>> mConnections;
    EventSignalWeakPtr[BaseEvent.Family] mConnections;
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
    void subscribe(E, Receiver)(Receiver receiver)
    {
        /*void (Receiver::*receive)(const E &) = &Receiver::receive;
        auto sig = signal_for(Event<E>::family());
        auto wrapper = EventCallbackWrapper<E>(std::bind(receive, &receiver, std::placeholders::_1));
        auto connection = sig->connect(wrapper);
        BaseReceiver &base = receiver;
        base.connections_.insert(std::make_pair(Event<E>::family(), std::make_pair(EventSignalWeakPtr(sig), connection)));*/
    }

    /**
     * Unsubscribe an object in order to not receive events of type E anymore.
     *
     * Receivers must have subscribed for event E before unsubscribing from event E.
     *
     */
    void unsubscribe(E, Receiver)(Receiver receiver)
    {
        BaseReceiver base = receiver;
        // Assert that it has been subscribed before
        /*assert(base.connections_.find(Event<E>::family()) != base.connections_.end());
        auto pair = base.connections_[Event<E>::family()];
        auto connection = pair.second;
        auto &ptr = pair.first;
        if (!ptr.expired())
          ptr.lock()->disconnect(connection);

        base.connections_.erase(Event<E>::family());*/
    }

    /**
     * Emit an already constructed event.
     */
    void emit(E)(E event)
    {
        /*auto sig = signal_for(Event<E>::family());
        sig->emit(event.get());*/
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
        /*auto sig = signal_for(std::size_t(Event<E>::family()));
        sig->emit(&event);*/
    }

    size_t nbConnectedReceivers()
    {
        return mHandlers.data.length;
    }

private:
    /*EventSignalPtr &signal_for(std::size_t id)
    {
      if (id >= handlers_.size())
        handlers_.resize(id + 1);
      if (!handlers_[id])
        handlers_[id] = std::make_shared<EventSignal>();
      return handlers_[id];
    }

    // Functor used as an event signal callback that casts to E.
    struct EventCallbackWrapper(E)
    {
      explicit EventCallbackWrapper(std::function<void(const E &)> callback) : callback(callback) {}
      void operator()(const void *event) { callback(*(static_cast<const E*>(event))); }
      std::function<void(const E &)> callback;
    };*/

    Appender!(EventSignalPtr[]) mHandlers;
}
