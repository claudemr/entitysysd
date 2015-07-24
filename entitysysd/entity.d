/**
Entity management module.

Copyright: © 2015 Claude Merle
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

module entitysysd.entity;

import std.bitmanip;
import std.container;
import std.string;

import entitysysd.component;
import entitysysd.event;
import entitysysd.exception;
import entitysysd.pool;

/// Attribute to use uppon component struct's and union's.
public import entitysysd.component : component;

/**
 * Entity structure.
 *
 * This is the combination of two 32-bits id: a unique-id and a version-id.
 */
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

        ulong id() const @property
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

        bool opEquals()(auto const ref Id lId) const
        {
            return id == lId.id;
        }

        string toString()
        {
            return format("#%d:%d", uniqueId, versionId);
        }

    private:
        ulong   mId;
    }

    enum Id invalid = Id(0, 0);

    this(EntityManager manager, Id id)
    {
        mManager = manager;
        mId = id;
    }

    /**
     * Destroy the entity.
     *
     * Throws: EntityException if the entity is invalid.
     */
    void destroy()
    {
        enforce!EntityException(valid);
        mManager.destroy(mId);
        invalidate();
    }

    /**
     * Tells whether the entity is valid.
     *
     * Returns: true if the entity is valid, false otherwise.
     */
    bool valid() @property
    {
        return mManager !is null && mManager.valid(mId);
    }

    /**
     * Invalidate the entity instance (but does not destroy it).
     */
    void invalidate()
    {
        mId = invalid;
        mManager = null;
    }

    /**
     * Returns the id of the entity.
     */
    Id id() const @property
    {
        return mId;
    }

    /**
     * Register a component C to an entity.
     *
     * Returns: A pointer on the component for this entity.
     *
     * Throws: EntityException if the entity is invalid.
     *         ComponentException if there is no room for that component or if
     *                            if the component is already registered.
     */
    C* register(C, Args...)(Args args)
        if (isComponent!C)
    {
        enforce!EntityException(valid);
        auto component = mManager.register!C(mId);
        static if (Args.length != 0)
            *component = C(args);
        return component;
    }

    /**
     * Unregister a component C from an entity.
     *
     * Throws: EntityException if the entity is invalid.
     *         ComponentException if the component is not registered.
     */
    void unregister(C)()
        if (isComponent!C)
    {
        enforce!EntityException(valid);
        mManager.unregister!C(mId);
    }

    /**
     * Get a component pointer of the entity.
     *
     * Returns: A pointer on the component for this entity.
     *
     * Throws: EntityException if the entity is invalid.
     *         ComponentException if the component is not registered.
     */
    C* component(C)() @property
        if (isComponent!C)
    {
        enforce!EntityException(valid);
        return mManager.getComponent!(C)(mId);
    }

    /**
     * Set the value of a component of the entity.
     *
     * Throws: EntityException if the entity is invalid.
     *         ComponentException if the component is not registered.
     */
    void component(C)(auto ref C c) @property
        if (isComponent!C)
    {
        enforce!EntityException(valid);
        *mManager.getComponent!(C)(mId) = c;
    }

    /**
     * Set the value of a component of the entity.
     *
     * Returns: true if the component is registered to the entity,
     *          false otherwise.
     *
     * Throws: EntityException if the entity is invalid.
     */
    bool isRegistered(C)()
        if (isComponent!C)
    {
        enforce!EntityException(valid);
        return mManager.isRegistered!C(mId);
    }

    /**
     * Compare two entities and tells whether they are the same (same id).
     */
    bool opEquals()(auto const ref Entity lEntity) const
    {
        return id == lEntity.id;
    }

    /**
     * Returns a string representation of an entity.
     *
     * It has the form: #uid:vid where uid is the unique-id and
     * vid is the version-id
     */
    string toString()
    {
        return mId.toString();
    }

private:
    EntityManager mManager;
    Id            mId = invalid;
}

///
unittest
{
    @component struct Position
    {
        float x, y;
    }

    auto em = new EntityManager(new EventManager);
    auto entity = em.create();
    auto posCompPtr = entity.register!Position(2.0, 3.0);
    assert(posCompPtr == entity.component!Position &&
           posCompPtr.x == 2.0 &&
           entity.component!Position.y == 3.0);
}

/**
 * Manages entities creation and component memory management.
 */
class EntityManager
{
public:
    /**
     * Constructor of the entity-manager. eventManager may be used to notify
     * about entity creation and component registration. maxComponent sets
     * the maximum number of components supported by the whole manager. poolSize
     * is the chunk size in bytes for each components.
     */
    this(EventManager eventManager,
         size_t maxComponent = 64,
         size_t poolSize     = 8192)
    {
        mEventManager = eventManager;
        mMaxComponent = maxComponent;
        mPoolSize     = poolSize;
    }

    /**
     * Current number of managed entities.
     */
    size_t size() @property
    {
        return mEntityComponentMask.length - mNbFreeIds;
    }

    /**
     * Current capacity entity.
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
     * Create an entity.
     *
     * Returns: a new valid entity.
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

        return entity;
    }

    /**
     * Returns an entity from an an entity-id
     *
     * Returns: the entity from the id.
     *
     * Throws: EntityException if the id is invalid.
     */
    Entity getEntity(Entity.Id id)
    {
        enforce!EntityException(valid(id));
        return Entity(this, id);
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
    auto components(C)() @property
        if (isComponent!C)
    {
        struct ComponentView(C)
            if (isComponent!C)
        {
            this(EntityManager em)
            {
                entityManager = em;
            }

            int opApply(int delegate(C* component) dg)
            {
                int result = 0;

                auto compId = entityManager.componentId!C();
                Pool!C pool = cast(Pool!C)entityManager.mComponentPools[compId];

                for (int i; i < pool.nbElements; i++)
                {
                    if (!entityManager.mEntityComponentMask[i][compId])
                        continue;
                    result = dg(&pool[i]);
                    if (result)
                        break;
                }

                return result;
            }

            EntityManager entityManager;
        }

        return ComponentView!C(this);
    }


    /**
     * Allows to browse through the entities that have a required set of
     * components.
     */
    auto entitiesWith(CList...)() @property
        if (areComponents!CList)
    {
        struct EntitiesWithView(CList...)
            if (areComponents!CList)
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
                        auto compId = entityManager.componentId!C();
                        if (!componentMask[compId])
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
        return EntitiesWithView!(CList)(this);
    }

private:
    void destroy(Entity.Id id)
    {
        uint uniqueId = id.uniqueId;

        // reset all components for that entity
        foreach (ref bit; mEntityComponentMask[uniqueId-1])
            bit = 0;
        // invalidate its version, incrementing it
        mEntityVersions[uniqueId-1]++;
        mFreeIds.insertFront(uniqueId);
        mNbFreeIds++;
    }

    C* register(C)(Entity.Id id)
        if (isComponent!C)
    {
        const auto compId = componentId!(C)();
        enforce!ComponentException(compId < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        enforce!ComponentException(!mEntityComponentMask[uniqueId-1][compId]);

        // place new component into the pools
        if (mComponentPools.length <= compId)
        {
            mComponentPools.length = compId + 1;
            mComponentPools[compId] = new Pool!C(mIndexCounter);
        }
        auto pool = cast(Pool!C)mComponentPools[compId];

        // Set the bit for this component.
        mEntityComponentMask[uniqueId-1][compId] = true;

        return &pool[uniqueId-1];
    }

    void unregister(C)(Entity.Id id)
        if (isComponent!C)
    {
        const auto compId = componentId!(C)();
        enforce!ComponentException(compId < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        enforce!ComponentException(mEntityComponentMask[uniqueId-1][compId]);

        // Remove component bit.
        mEntityComponentMask[uniqueId-1][compId] = false;
    }

    bool isRegistered(C)(Entity.Id id)
        if (isComponent!C)
    {
        const auto compId = componentId!(C)();
        const auto uniqueId = id.uniqueId;

        if (compId >= mMaxComponent)
            return false;

        return mEntityComponentMask[uniqueId-1][compId];
    }

    C* getComponent(C)(Entity.Id id)
        if (isComponent!C)
    {
        const auto compId = componentId!(C)();
        enforce!ComponentException(compId < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        enforce!ComponentException(mEntityComponentMask[uniqueId-1][compId]);

        // Placement new into the component pool.
        Pool!C pool = cast(Pool!C)mComponentPools[compId];
        return &pool[uniqueId-1];
    }

    size_t componentId(C)()
    {
        return ComponentCounter!(C).getId();
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

    // Current number of Entities
    uint            mIndexCounter = 0;
    size_t          mMaxComponent;
    size_t          mPoolSize;
    // Event Manager
    EventManager    mEventManager;
    // Array of pools for each component types
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


//******************************************************************************
//***** UNIT-TESTS
//******************************************************************************

import std.stdio;

unittest
{
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

    @component struct NameComponent
    {
        string name;
    }

    @component struct PosComponent
    {
        int x, y;
    }

    ent0.register!NameComponent();
    ent1.register!NameComponent();
    ent2.register!NameComponent();

    ent0.register!PosComponent();
    ent2.register!PosComponent();

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