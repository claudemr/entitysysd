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

    void destroy()
    {
        assert(valid);
        mManager.destroy(mId);
        invalidate();
    }

    bool valid() @property
    {
        return mManager !is null && mManager.valid(mId);
    }

    void invalidate()
    {
        mId = invalid;
        mManager = null;
    }

    Id id() const @property
    {
        return mId;
    }

    C* register(C)()
    {
        assert(valid);
        return mManager.register!C(mId);
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

    bool opEquals()(auto const ref Entity lEntity) const
    {
        return id == lEntity.id;
    }

    string toString()
    {
        return mId.toString();
    }

private:
    EntityManager mManager;
    Id            mId = invalid;
}


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

    C* register(C)(Entity.Id id)
    {
        assertValid(id);
        const auto compId = componentId!(C)();
        assert(compId < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        assert(!mEntityComponentMask[uniqueId-1][compId]);

        // Placement new into the component pool.
        auto pool = accomodateComponent!(C)();

        // Set the bit for this component.
        mEntityComponentMask[uniqueId-1][compId] = true;

        return &pool[uniqueId-1];
    }

    void unregister(C)(Entity.Id id)
    {
        assertValid(id);
        const auto compId = componentId!(C)();
        assert(compId < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        assert(mEntityComponentMask[uniqueId-1][compId]);

        // Remove component bit.
        mEntityComponentMask[uniqueId-1][compId] = false;
    }

    bool isRegistered(C)(Entity.Id id)
    {
        assertValid(id);
        const auto compId = componentId!(C)();
        const auto uniqueId = id.uniqueId;

        if (compId >= mMaxComponent)
            return false;

        return mEntityComponentMask[uniqueId-1][compId];
    }

    C* getComponent(C)(Entity.Id id)
    {
        assertValid(id);
        const auto compId = componentId!(C)();
        assert(compId < mMaxComponent);
        const auto uniqueId = id.uniqueId;
        assert(mEntityComponentMask[uniqueId-1][compId]);

        // Placement new into the component pool.
        Pool!C pool = cast(Pool!C)mComponentPools[compId];
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

    Pool!C accomodateComponent(C)()
    {
        auto compId = componentId!C();

        if (mComponentPools.length <= compId)
        {
            mComponentPools.length = compId + 1;
            mComponentPools[compId] = new Pool!C(mIndexCounter);
        }
        return cast(Pool!C)mComponentPools[compId];
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