/**
Entity management module.

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
     * Destroy the entity (unregister all attached components).
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
     * Params:
     *   C    = Component to register.
     *   args = List of arguments to initialize the component, will be passed to
     *          its constructor. Optional.
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
     * Params:
     *   C  = Component to unregister.
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
     * Params:
     *   C  = Component for the entity.
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
     * Params:
     *   C  = Component to set.
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
     * Tell whether a component is registered to the entity.
     *
     * Params:
     *   C  = Component to test.
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
     * Iterate over the components registered to the entity. It calls the
     * accessor delegate that has been set to each component.
     *
     * Throws: EntityException if the entity is invalid.
     */
    void iterate()
    {
        enforce!EntityException(valid);
        mManager.iterate(this);
    }

    /**
     * Compare two entities and tells whether they are the same (same id).
     */
    bool opEquals()(auto const ref Entity e) const
    {
        return id == e.id;
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

    assert(posCompPtr == entity.component!Position);
    assert(posCompPtr.x == 2.0);
    assert(entity.component!Position.y == 3.0);
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
     *
     * Examples:
     * --------------------
     * foreach (entity; entityManager)
     * { ... }
     * --------------------
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
     * Return a range of all the valid instances of a component.
     */
    auto components(C)() @property
        if (isComponent!C)
    {
        import std.range : iota;
        import std.algorithm : map, filter;

        immutable compId = componentId!C();

        // if no such component has ever been registered, no pool will exist.
        auto pool = cast(Pool!C)mComponentPools[compId];
        assert(pool !is null, "A component pool should never be null");

        return iota(0, pool.nbElements)
            .filter!(i => mEntityComponentMask[i][compId])
            .map!(i => &pool[i]);
    }

    /**
     * Allows to browse through the entities that have a required set of
     * components.
     *
     * Examples:
     * --------------------
     * foreach (entity; entityManager.entitiesWith!(CompA, CompB))
     * { ... }
     * --------------------
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

            int opApply(int delegate(Entity entity, Pointers!CList components) dg)
            {
                auto withComponents(Entity ent)
                {
                    auto get(T)()
                    {
                        return ent.component!T;
                    }
                    import std.meta : staticMap;
                    return dg(ent, staticMap!(get, CList));
                }

                return opApply(&withComponents);
            }

            EntityManager entityManager;
        }
        return EntitiesWithView!(CList)(this);
    }

    alias CompAccessor = void delegate(Entity e, void* pc);

    /**
     * Set an accessor delegate for a component.
     *
     * Params:
     *   C  = Component to which the accessor delegate will be set.
     *   dg = Delegate that will be called when using $(D Entity.iterate).
     */
    void setAccessor(C)(void delegate(Entity e, C* pc) dg)
    {
        immutable compId = ComponentCounter!(C).getId();
        // Make sure the delegate array is large enough
        if (mComponentAccessors.length <= compId)
            mComponentAccessors.length = compId + 1;
        mComponentAccessors[compId] = cast(CompAccessor)dg;
    }

    /**
     * Clears an accessor delegate for a component.
     *
     * Params:
     *   C  = Component to which the accessor delegate will be cleared.
     */
    void clearAccessor(C)()
    {
        immutable compId = ComponentCounter!(C).getId();
        // If this Make sure the delegate array is large enough
        if (mComponentAccessors.length <= compId)
            return;
        mComponentAccessors[compId] = null;
    }

    /**
     * Get the accessor delegate assigned to a component.
     *
     * Params:
     *   C  = Component from which the accessor delegate will be retreived.
     *
     * Returns:
     *   The accessor delegate; null if it has never been set or if the
     *   component is missing.
     */
    void delegate(Entity e, C* pc) getAccessor(C)()
    {
        immutable compId = ComponentCounter!(C).getId();
        if (mComponentAccessors.length <= compId)
            return null;
        return cast(void delegate(Entity e, C* pc))mComponentAccessors[compId];
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
        auto pool = cast(Pool!C)mComponentPools[compId];
        assert(pool !is null, "A component pool should never be null");

        // Set the bit for this component.
        mEntityComponentMask[uniqueId-1][compId] = true;

        pool.initN(uniqueId-1);

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
        immutable compId = ComponentCounter!(C).getId();

        // ensure we have a pool to hold components of this type
        if (mComponentPools.length <= compId)
        {
            mComponentPools.length = compId + 1;
            mComponentPools[compId] = new Pool!C(mIndexCounter);
        }

        return compId;
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

    void iterate(Entity entity)
    {
        const auto uniqueId = entity.id.uniqueId;

        // Iterate over all components registered to that entity
        foreach (compId; 0..mComponentAccessors.length)
        {
            // If the component is registered and has a delegate
            if (mEntityComponentMask[uniqueId-1][compId])
                if (mComponentAccessors[compId] !is null)
                {
                    auto compPtr = mComponentPools[compId].getPtr(uniqueId-1);
                    mComponentAccessors[compId](entity, compPtr);
                }
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
    // Bitmask of components for each entities
    // Index into the vector is the Entity.Id
    BitArray[]      mEntityComponentMask;
    // Array of delegates for each component
    CompAccessor[]  mComponentAccessors;
    // Vector of entity version id's
    // Incremented each time an entity is destroyed
    uint[]          mEntityVersions;
    // List of available entity id's.
    SList!uint      mFreeIds;
    uint            mNbFreeIds;
}

// Translate a list of types to a list of pointers to those types.
private template Pointers(T...)
{
    import std.meta : staticMap;
    private alias PtrTo(U) = U*;
    alias Pointers = staticMap!(PtrTo, T);
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

    // Check const fields are properly handled
    @component struct ConstComp
    {
        int           a, b;
        const float   cFloat = 5.0;
        immutable int iInt = 5;
    }

    ent0.register!ConstComp();
    assert(ent0.component!ConstComp.cFloat == 5.0);

    // Check immutable fields are not accepted
    @component struct ImmutableComp
    {
        int             a, b;
        shared    float sFloat = 5.0;
        __gshared float gsFloat = 5.0;
    }

    // Check it will NOT compile if a field is shared
    assert(!__traits(compiles, ent0.register!ImmutableComp()));
}

unittest
{
    @component struct Velocity { int x, y; }
    @component struct Position { int x, y; }

    auto em = new EntityManager(new EventManager());

    auto ent0 = em.create();
    auto ent1 = em.create();

    ent0.register!Position(0, 0);
    ent1.register!Position(4, 5);

    ent0.register!Velocity(1, 2);
    ent1.register!Velocity(3, 4);

    // test getting components from the opApply loop
    foreach(ent, pos, vel; em.entitiesWith!(Position, Velocity))
    {
        pos.x += vel.x;
        pos.y += vel.y;
    }

    assert(ent0.component!Position.x == 1 && ent0.component!Position.y == 2);
    assert(ent1.component!Position.x == 7 && ent1.component!Position.y == 9);
}

// Ensure that em.components!T does not throw if no `T` has ever been registered
unittest
{
    @component struct Dummy { }

    auto em = new EntityManager(new EventManager());

    foreach(pos ; em.components!Dummy)
        assert(0, "Loop should never be entered");
}

// Validate fix for a bug where you could end up with uninitialized pools.
// ent.isRegistered would create room for a pool without allocating it,
// potentially creating null pools in the middle of the collection.
// register was only checking the collection length, but did not ensure that the
// pool it retrieved to store the component was non-null.
unittest
{
    @component struct Dummy1 { }
    @component struct Dummy2 { }

    auto em = new EntityManager(new EventManager());
    auto ent = em.create();

    assert(!ent.isRegistered!Dummy1);
    assert(!ent.isRegistered!Dummy2);
    assert(ent.register!Dummy2);
    assert(ent.register!Dummy1);
}

// Test range interface for components!T
unittest
{
    @component struct A
    {
        int a;
    }

    @component struct B
    {
        string b;
    }

    auto em = new EntityManager(new EventManager());

    auto e1 = em.create();
    auto e2 = em.create();
    auto e3 = em.create();

    e1.register!A(1);
    e2.register!B("2");
    e3.register!A(3);
    e3.register!B("3");

    import std.algorithm : map, equal;
    assert(em.components!A.map!(x => x.a).equal([1, 3]));
    assert(em.components!B.map!(x => x.b).equal(["2", "3"]));
}


// Test component accessors
unittest
{
    import std.conv;
    string output;

    @component struct A
    {
        int i;
    }

    @component struct B
    {
        string str;
    }

    auto em = new EntityManager(new EventManager());

    auto e1 = em.create();
    auto e2 = em.create();
    auto e3 = em.create();

    e1.register!A(1);
    e2.register!B("hello");
    e3.register!A(3);
    e3.register!B("world");

    void accessorForA(Entity e, A* a)
    {
        assert(e == e1 || e == e3);
        output ~= a.i.to!string;
    }

    em.setAccessor!A(&accessorForA);
    em.setAccessor!B((e, b) { output ~= b.str; }); // use lambda

    e1.iterate();
    assert(output == "1");

    output = "";
    e2.iterate();
    assert(output == "hello");

    output = "";
    e3.iterate();
    assert(output == "3world");
}