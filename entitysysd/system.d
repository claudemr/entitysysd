module entitysysd.system;

import std.array;
import entitysysd.component;
import entitysysd.entity;
import entitysysd.event;

//todo use specific D time stuff
alias TimeDelta = ulong;

/**
 * Base System class. Generally should not be directly used, instead see System<Derived>.
 */
class BaseSystem
{
    /**
     * Called once all Systems have been added to the SystemManager.
     *
     * Typically used to set up event handlers.
     */
    void configure(BaseEntityManager entities, EventManager events)
    {
        configure(events);
    }

    /**
     * Legacy configure(). Called by default implementation of configure(EntityManager&, EventManager&).
     */
    void configure(EventManager events)
    {
    }

    /**
     * Apply System behavior.
     *
     * Called every game step.
     */
    void update(BaseEntityManager entities, EventManager events, TimeDelta dt)
    {
    }
};


/**
 * Use this class when implementing Systems.
 *
 * struct MovementSystem : public System<MovementSystem> {
 *   void update(EntityManager &entities, EventManager &events, TimeDelta dt) {
 *     // Do stuff to/with entities...
 *   }
 * }
 */
class System(Derived) : BaseSystem
{
public:
    //virtual ~System() {}

private:
};


class SystemManager
{
public:
    this(BaseEntityManager entityManager,
         EventManager eventManager)
    {
        mEntityManager = entityManager;
        mEventManager  = eventManager;
    }

    /**
     * Add a System to the SystemManager.
     *
     * Must be called before Systems can be used.
     *
     * eg.
     * std::shared_ptr<MovementSystem> movement = entityx::make_shared<MovementSystem>();
     * system.add(movement);
     */
    void add(S)(S system)
    {
        mSystems.put(system);
    }

    /**
     * Add a System to the SystemManager.
     *
     * Must be called before Systems can be used.
     *
     * eg.
     * auto movement = system.add<MovementSystem>();
     */
    S add(S, Args...)(Args args)
    {
        auto s = new S(Args);
        add(s);
        return s;
    }

    /**
     * Retrieve the registered System instance, if any.
     *
     *   std::shared_ptr<CollisionSystem> collisions = systems.system<CollisionSystem>();
     *
     * @return System instance or empty shared_std::shared_ptr<S>.
     */
    S system(S)() @property
    {
        //todo
        /*auto it = systems_.find(S::family());
        assert(it != systems_.end());
        return it == systems_.end()
            ? std::shared_ptr<S>()
            : std::shared_ptr<S>(std::static_pointer_cast<S>(it->second));*/
    }

    /**
     * Call the System::update() method for a registered system.
     */
    void update(S)(TimeDelta dt)
    {
        assert(initialized_, "SystemManager::configure() not called");
        auto s = system!(S)();
        s.update(entity_manager_, event_manager_, dt);
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
    void updateAll(TimeDelta dt)
    {
        assert(mInitialized, "SystemManager.configure() not called");
        foreach (s; mSystems.data)
            s.update(mEntityManager, mEventManager, dt);
    }

    /**
     * Configure the system. Call after adding all Systems.
     *
     * This is typically used to set up event handlers.
     */
    void configure()
    {
        foreach (s; mSystems.data)
            s.configure(mEntityManager, mEventManager);
        mInitialized = true;
    }

private:
    bool                    mInitialized;
    BaseEntityManager       mEntityManager;
    EventManager            mEventManager;
    Appender!(BaseSystem[]) mSystems;
}


unittest
{
    class Position : Component!(Position)
    {
        float x, y;
    }

    class Direction : Component!(Direction)
    {
        float x, y;
    }

    class Counter : Component!(Counter)
    {
        int counter;
    }

    class MovementSystem : System!(MovementSystem)
    {
    public:
        override
        void update(EntityManager em, EventManager events, TimeDelta td)
        {
            EntityManager.View entities =
                em.entitiesWithComponents!(Position, Direction)();
            ComponentHandle!(Position)  position;
            ComponentHandle!(Direction) direction;
            foreach (entity; entities)
            {
                entity.unpack!(Position, Direction)(position, direction);
                position.x += direction.x;
                position.y += direction.y;
            }
        }

    private:
        string mLabel;
    }

    class CounterSystem : System!(CounterSystem)
    {
        override
        void update(EntityManager em, EventManager events, TimeDelta td)
        {
            EntityManager.View entities =
                em.entitiesWithComponents!(Counter)();
            Counter.Handle counter;
            foreach (entity; entities)
            {
                entity.unpack!(Counter)(counter);
                counter.counter++;
            }
        }
    }

    class EntitiesFixture : EntitySysD
    {
    private:
        Appender!(Entity[]) mCreatedEntities;

    public:

        this()
        {
            for (int i = 0; i < 150; ++i)
            {
                Entity e = entities.create();
                mCreatedEntities.put(e);
                if (i % 2 == 0)
                    e.assign!(Position)(1, 2);
                if (i % 3 == 0)
                    e.assign!(Direction)(1, 1);

                e.assign!(Counter)(0);
            }
        }
    }

    {
      systems.add!(MovementSystem)("movement");
      systems.configure();

      assert("movement" == systems.system!(MovementSystem)().label);
    }
/+
    TEST_CASE_METHOD(EntitiesFixture, "TestApplySystem") {
      systems.add<MovementSystem>();
      systems.configure();

      systems.update<MovementSystem>(0.0);
      ComponentHandle<Position> position;
      ComponentHandle<Direction> direction;
      for (auto entity : created_entities) {
        entity.unpack<Position, Direction>(position, direction);
        if (position && direction) {
          REQUIRE(2.0 == Approx(position->x));
          REQUIRE(3.0 == Approx(position->y));
        } else if (position) {
          REQUIRE(1.0 == Approx(position->x));
          REQUIRE(2.0 == Approx(position->y));
        }
      }
    }

    TEST_CASE_METHOD(EntitiesFixture, "TestApplyAllSystems") {
      systems.add<MovementSystem>();
      systems.add<CounterSystem>();
      systems.configure();

      systems.update_all(0.0);
      Position::Handle position;
      Direction::Handle direction;
      Counter::Handle counter;
      for (auto entity : created_entities) {
        entity.unpack<Position, Direction, Counter>(position, direction, counter);
        if (position && direction) {
          REQUIRE(2.0 == Approx(position->x));
          REQUIRE(3.0 == Approx(position->y));
        } else if (position) {
          REQUIRE(1.0 == Approx(position->x));
          REQUIRE(2.0 == Approx(position->y));
        }
        REQUIRE(1 == counter->counter);
      }
    }+/
}
