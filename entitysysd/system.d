module entitysysd.system;

public import core.time;
import std.algorithm;
import std.container;
import std.range;

import entitysysd.entity;
import entitysysd.event;


/**
 * System interface.
 */
interface System
{
    /**
     * Called once all Systems have been added to the SystemManager.
     *
     * Typically used to set up event handlers.
     */
    void configure(EntityManager entities, EventManager events);

    /**
     * Apply System behavior.
     *
     * Called every game step.
     */
    void update(EntityManager entities, EventManager events, Duration dt);
}


class SystemManager
{
public:
    this(EntityManager entityManager,
         EventManager  eventManager)
    {
        mEntityManager = entityManager;
        mEventManager  = eventManager;
    }

    void insert(System system)
    {
        auto sysNode = mSystems[].find(system);
        if (!sysNode.empty)
        	return;
        mSystems ~= system;
    }

    void remove(System system)
    {
        auto sysNode = mSystems[].find(system);
        if (sysNode.empty)
        	return;
        mSystems.linearRemove(sysNode.take(1));
    }

    /**
     * Call System::update() on all registered systems.
     *
     * The order which the registered systems are updated is arbitrary but consistent,
     * meaning the order which they will be updated cannot be specified, but that order
     * will stay the same as long no systems are added or removed.
     *
     * If the order in which systems update is important, use SystemManager::update()
     * to manually specify the update order. EntityX does not yet support a way of
     * specifying priority for update_all().
     */
    void update(Duration dt)
    {
        if (!mInitialized)
        	return;
        foreach (s; mSystems)
            s.update(mEntityManager, mEventManager, dt);
    }

    /**
     * Configure the system. Call after adding all Systems.
     *
     * This is typically used to set up event handlers.
     */
    void configure()
    {
        foreach (s; mSystems)
            s.configure(mEntityManager, mEventManager);
        mInitialized = true;
    }

private:
    bool          mInitialized;
    EntityManager mEntityManager;
    EventManager  mEventManager;
    DList!System  mSystems;
}
