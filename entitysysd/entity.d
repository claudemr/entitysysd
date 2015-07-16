module entitysysd.entity;

import std.bitmanip;
import std.container;
import std.string;

import entitysysd.component;
import entitysysd.event;
import entitysysd.pool;



struct Entity
{
public:
    static struct Id
    {
    public:
        this(uint uId, uint vId)
        {
            mId = cast(ulong)uId | cast(ulong)vId << 32;
        }

        ulong id() @property
        {
            return mId;
        }
        uint uniqueId() @property
        {
            return mId & 0xffffffffUL;
        }
        uint versionId() @property
        {
            return mId >> 32;
        }

        string toString()
        {
            return format("#%d:%d", uniqueId, versionId);
        }

    private:
        //friend class EntityManager;
        ulong   mId;
    }

    enum Id invalid = Id(0, 0);

    this(EntityManager manager, Id id)
    {
        mManager = manager;
        mId = id;
    }

    /**
     * Destroy and invalidate this Entity.
     */
    void destroy()
    {
        assert(valid);
        mManager.destroy(mId);
        invalidate();
    }

    /**
     * Is this Entity handle valid?
     */
    bool valid() @property
    {
        return mManager !is null && mManager.valid(mId);
    }

    /**
     * Invalidate Entity handle, disassociating it from an EntityManager and invalidating its ID.
     *
     * Note that this does *not* affect the underlying entity and its
     * components. Use destroy() to destroy the associated Entity and components.
     */
    void invalidate()
    {
        mId = invalid;
        mManager = null;
    }

    Id id() @property
    {
        return mId;
    }

    void insert(C)()
    {
        assert(valid);
        mManager.insert!C(mId);
    }

    void remove(C)()
    {
        assert(valid);
        mManager.remove!C(mId);
    }

    C* component(C)() @property
    {
        assert(valid);
        return mManager.getComponent!(C)(mId);
    }

    void component(C)(C c) @property
    {
        assert(valid);
        *mManager.getComponent!(C)(mId) = c;
    }

    bool has(C)()
    {
        assert(valid);
        return mManager.has!C(mId);
    }

    string toString()
    {
        return mId.toString();
    }

private:
    EntityManager mManager;
    Id            mId = invalid;
}


/+
/**
 * Emitted when an entity is added to the system.
 */
struct EntityCreatedEvent
{
    alias event this;

    this(Entity lEntity)
    {
        entity = lEntity;
    }

    Entity entity;
    Event!(EntityCreatedEvent) event;
}


/**
 * Called just prior to an entity being destroyed.
 */
struct EntityDestroyedEvent
{
    alias event this;

    this(Entity lEntity)
    {
        entity = lEntity;
    }

    Entity entity;
    Event!(EntityDestroyedEvent) event;
}
+/


/**
 * Manages Entity.Id creation and component assignment.
 */
class EntityManager
{
public:
    this(EventManager eventManager,
         size_t maxComponent = 64,
         size_t poolSize     = 8192)
    {
        mEventManager = eventManager;
        mMaxComponent = maxComponent;
        mPoolSize     = poolSize;
    }

    /**
     * Number of managed entities.
     */
    size_t size() @property
    {
        return mEntityComponentMask.length - mNbFreeIds;
    }

    /**
     * Current entity capacity.
     */
    size_t capacity() @property
    {
        return mEntityComponentMask.length;
    }

    /**
     * Return true if the given entity ID is still valid.
     */
    bool valid(Entity.Id id)
    {
        return id != Entity.invalid &&
               id.uniqueId-1 < mEntityVersions.length &&
               mEntityVersions[id.uniqueId-1] == id.versionId;
    }

    /**
     * Create a new Entity.Id.
     *
     * Emits EntityCreatedEvent.
     */
    Entity create()
    {
        uint uniqueId, versionId;

        if (mFreeIds.empty)
        {
            mIndexCounter++;
            uniqueId = mIndexCounter;
            accomodateEntity();
            versionId = mEntityVersions[uniqueId-1];
        }
        else
        {
            uniqueId = mFreeIds.front;
            mFreeIds.removeFront();
            mNbFreeIds--;
            versionId = mEntityVersions[uniqueId-1];
        }

        Entity entity = Entity(this, Entity.Id(uniqueId, versionId));

        //todo ?
        //mEventManager.emit!(EntityCreatedEvent)(entity);
        return entity;
    }

    /**
     * Destroy an existing Entity.Id and its associated Components.
     *
     * Emits EntityDestroyedEvent.
     */
    void destroy(Entity.Id id)
    {
        assertValid(id);

        uint uniqueId = id.uniqueId;

        // reset all components for that entity
        foreach (ref bit; mEntityComponentMask[uniqueId-1])
            bit = 0;
        // invalidate its version, incrementing it
        mEntityVersions[uniqueId-1]++;
        mFreeIds.insertFront(uniqueId);
        mNbFreeIds++;
    }

    Entity getEntity(Entity.Id id)
    {
        assertValid(id);
        return Entity(this, id);
    }

    void insert(C)(Entity.Id id)
    {
        assertValid(id);
        const BaseComponent.Family family = componentFamily!(C)();
        assert(family < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        assert(!mEntityComponentMask[uniqueId-1][family]);

        // Placement new into the component pool.
        Pool!(C) *pool = accomodateComponent!(C)();

        // Set the bit for this component.
        mEntityComponentMask[uniqueId-1][family] = true;
    }

    /**
     * Remove a Component from an Entity.Id
     *
     * Emits a ComponentRemovedEvent<C> event.
     */
    void remove(C)(Entity.Id id)
    {
        assertValid(id);
        const BaseComponent.Family family = componentFamily!(C)();
        assert(family < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        assert(mEntityComponentMask[uniqueId-1][family]);

        // Remove component bit.
        mEntityComponentMask[uniqueId-1][family] = false;
    }

    /**
     * Check if an Entity has a component.
     */
    bool has(C)(Entity.Id id)
    {
        assertValid(id);
        const BaseComponent.Family family = componentFamily!(C)();
        const auto uniqueId = id.uniqueId;

        if (family >= mMaxComponent)
            return false;

        return mEntityComponentMask[uniqueId-1][family];
    }

    /**
     * Retrieve a Component assigned to an Entity.Id.
     *
     * @returns Pointer to an instance of C, or nullptr if the Entity.Id does not have that Component.
     */
    C* getComponent(C)(Entity.Id id)
    {
        assertValid(id);
        const BaseComponent.Family family = componentFamily!(C)();
        assert(family < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        assert(mEntityComponentMask[uniqueId-1][family]);

        // Placement new into the component pool.
        Pool!C pool = cast(Pool!C)mComponentPools[family];
        return &pool[uniqueId-1];
    }

    //*** Browsing features ***

    /**
     * Allows to browse through all the valid entities of the manager with
     * a foreach loop.
     */
    int opApply(int delegate(Entity entity) dg)
    {
        int result = 0;

        // copy version-ids
        auto versionIds = mEntityVersions.dup;
        // and remove those that are free
        foreach (freeId; mFreeIds)
            versionIds[freeId-1] = uint.max;

        foreach (uniqueId, versionId; versionIds)
        {
            if (versionId == uint.max)
                continue;
            result = dg(Entity(this,
                               Entity.Id(cast(uint)uniqueId+1, versionId)));
            if (result)
                break;
        }

        return result;
    }


    /**
     * Allows to browse through all the valid instances of a component with
     * a foreach loop.
     */
    struct ComponentView(C)
    {
        this(EntityManager em)
        {
            entityManager = em;
        }

        int opApply(int delegate(C* component) dg)
        {
            int result = 0;

            BaseComponent.Family family = entityManager.componentFamily!C();
            Pool!C pool = cast(Pool!C)entityManager.mComponentPools[family];

            for (int i; i < pool.nbElements; i++)
            {
                if (!entityManager.mEntityComponentMask[i][family])
                    continue;
                result = dg(&pool[i]);
                if (result)
                    break;
            }

            return result;
        }

        EntityManager entityManager;
    }

    ComponentView!C components(C)() @property
    {
        return ComponentView!C(this);
    }

    /**
     * Allows to browse through the entities that have a required set of
     * components.
     */
    struct EntitiesWithView(CList...)
    {
        this(EntityManager em)
        {
            entityManager = em;
        }

        int opApply(int delegate(Entity entity) dg)
        {
            int result = 0;

            entityLoop: foreach (i, ref componentMask;
                                 entityManager.mEntityComponentMask)
            {
                foreach (C; CList)
                {
                    auto family = entityManager.componentFamily!C();
                    if (!componentMask[family])
                        continue entityLoop;
                }

                auto versionId = entityManager.mEntityVersions[i];
                result = dg(Entity(entityManager,
                                   Entity.Id(cast(uint)i+1, versionId)));
                if (result)
                    break;
            }

            return result;
        }

        EntityManager entityManager;
    }

    EntitiesWithView!(CList) entitiesWith(CList...)() @property
    {
        return EntitiesWithView!(CList)(this);
    }

private:
    void assertValid(Entity.Id id)
    {
        assert(id.uniqueId-1 < mEntityComponentMask.length, "Entity.Id ID outside entity vector range");
        assert(mEntityVersions[id.uniqueId-1] == id.versionId, "Attempt to access Entity via an obsolete Entity.Id");
    }

    BaseComponent.Family componentFamily(C)()
    {
        return Component!(C).family();
    }

    void accomodateEntity()
    {
        if (mEntityComponentMask.length < mIndexCounter)
        {
            mEntityComponentMask.length = mIndexCounter;
            foreach (ref mask; mEntityComponentMask)
                mask.length = mMaxComponent;
            mEntityVersions.length = mIndexCounter;
            foreach (ref pool; mComponentPools)
                pool.accomodate(mIndexCounter);
        }
    }

    Pool!C* accomodateComponent(C)()
    {
        BaseComponent.Family family = componentFamily!C();

        if (mComponentPools.length <= family)
        {
            mComponentPools.length = family + 1;
            mComponentPools[family] = new Pool!C(mIndexCounter);
        }
        return cast(Pool!C*)&mComponentPools[family];
    }


    // Current number of Entities
    uint            mIndexCounter = 0;
    size_t          mMaxComponent;
    size_t          mPoolSize;
    // Event Manager
    EventManager    mEventManager;
    // Array of pools for each component family
    BasePool[]      mComponentPools;
    // Bitmask of components for each entities.
    // Index into the vector is the Entity.Id.
    BitArray[]      mEntityComponentMask;
    // Vector of entity version id's
    // Incremented each time an entity is destroyed
    uint[]          mEntityVersions;
    // List of available entity id's.
    SList!uint      mFreeIds;
    uint            mNbFreeIds;
}

import std.stdio;

unittest
{
    //dmd -main -unittest entitysysd/entity.d entitysysd/component.d entitysysd/event.d entitysysd/pool.d

    auto em = new EntityManager(new EventManager());

    auto ent0 = em.create();
    assert(em.capacity == 1);
    assert(em.size == 1);
    assert(ent0.valid);
    assert(ent0.id.uniqueId == 1);
    assert(ent0.id.versionId == 0);

    ent0.destroy();
    assert(em.capacity == 1);
    assert(em.size == 0);
    assert(!ent0.valid);
    assert(ent0.id.uniqueId == 0);
    assert(ent0.id.versionId == 0);

    ent0 = em.create();
    auto ent1 = em.create();
    auto ent2 = em.create();
    assert(em.capacity == 3);
    assert(em.size == 3);
    assert(ent0.id.uniqueId == 1);
    assert(ent0.id.versionId == 1);
    assert(ent1.id.uniqueId == 2);
    assert(ent1.id.versionId == 0);
    assert(ent2.id.uniqueId == 3);
    assert(ent2.id.versionId == 0);

    struct NameComponent
    {
        string name;
    }

    struct PosComponent
    {
        int x, y;
    }

    ent0.insert!NameComponent();
    ent1.insert!NameComponent();
    ent2.insert!NameComponent();

    ent0.insert!PosComponent();
    ent2.insert!PosComponent();

    ent0.component!NameComponent.name = "Hello";
    ent1.component!NameComponent.name = "World";
    ent2.component!NameComponent.name = "Again";
    assert(ent0.component!NameComponent.name == "Hello");
    assert(ent1.component!NameComponent.name == "World");
    assert(ent2.component!NameComponent.name == "Again");

    ent0.component!PosComponent = PosComponent(5, 6);
    ent2.component!PosComponent = PosComponent(2, 3);
    assert(ent0.component!PosComponent.x == 5);
    assert(ent0.component!PosComponent.y == 6);
    assert(ent2.component!PosComponent.x == 2);
    assert(ent2.component!PosComponent.y == 3);

    //ent1.destroy();

    // List all current valid entities
    foreach (ent; em)
    {
        assert(ent.valid);
        //writeln(ent.component!NameComponent.name);
    }

    // List all name components
    foreach (comp; em.components!NameComponent)
    {
        //writeln(comp.name);
    }

    // List all name components
    foreach (ent; em.entitiesWith!(NameComponent, PosComponent))
    {
        assert(ent.valid);
        //writeln(ent.component!NameComponent.name);
    }
}