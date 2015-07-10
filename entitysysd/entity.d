module entitysysd.entity;

import std.container;

import entitysysd.bitarray;
import entitysysd.component;
import entitysysd.event;
import entitysysd.pool;



struct Entity
{
public:
    static struct Id
    {
    public:
        this(uint uniqueId, uint versionId)
        {
            mId = uniqueId + cast(ulong)versionId << 32;
        }

        /*bool operator == (const Id &other) const { return id_ == other.id_; }
        bool operator != (const Id &other) const { return id_ != other.id_; }
        bool operator < (const Id &other) const { return id_ < other.id_; }*/

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

    private:
        //friend class EntityManager;
        ulong   mId;
    }

    enum Id invalid = Id(0, 0);

    this(BaseEntityManager manager, Id id)
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

    /+operator bool() const {
    return valid();
  }
  bool operator == (const Entity &other) const {
    return other.manager_ == manager_ && other.id_ == id_;
  }
  bool operator != (const Entity &other) const {
    return !(other == *this);
  }
  bool operator < (const Entity &other) const {
    return other.id_ < id_;
  }+/

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


    /+ComponentHandle!(C) assign(C, Args...)(Args args)
    {
        assert(valid);
        return mManager.assign!(C, Args)(mId, args);
    }

    /*template <typename C>
    ComponentHandle<C> assign_from_copy(const C &component);*/

    ComponentHandle!(C) replace(C, Args...)(Args args)
    {
        assert(valid);
        auto handle = component!(C)();
        if (handle !is null)
            handle.get() = C(args);
        else
            handle = mManager.assign!(C)(mId, args);
        return handle;
    }+/

    void remove(C, Args...)(Args args)
    {
        assert(valid);
        mManager.remove!(C, Args)(mId, args);
    }

    /+ComponentHandle!(C) component(C)()
    {
        assert(valid());
        return mManager.component!(C)(mId);
    }+/

    /*template <typename C, typename = typename std::enable_if<std::is_const<C>::value>::type>
    const ComponentHandle<C, const EntityManager> component() const;*/

    /*template <typename ... Components>
    std::tuple<ComponentHandle<Components>...> components();*/

    /*template <typename ... Components>
    std::tuple<ComponentHandle<const Components, const EntityManager>...> components() const;*/

    bool hasComponent(C)()
    {
        assert(valid);
        return mManager.hasComponent!(C, Args)(mId, args);
    }

    /+void unpack(A, Args...)(ComponentHandle!(A) a, Args args)
    {
        assert(valid);
        mManager.hasComponent!(C, Args)(mId, args);
    }+/

private:
    BaseEntityManager mManager;
    Id                mId = invalid;
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

interface BaseEntityManager
{
    Entity create();
    void destroy(Entity.Id entityId);

    size_t size() @property;
    size_t capacity() @property;
    bool   valid(Entity.Id id);
}

/**
 * Manages Entity.Id creation and component assignment.
 */
class EntityManager(size_t MaxComponent) : BaseEntityManager
{
public:
    this(EventManager eventManager)
    {
        mEventmanager = eventManager;
    }
    //virtual ~EntityManager();

    /// An iterator over a view of the entities in an EntityManager.
    /// If All is true it will iterate over all valid entities and will ignore the entity mask.
    /+class ViewIterator(Delegate, bool All = false)// : public std::iterator<std::input_iterator_tag, Entity.Id>
    {
     public:
      Delegate &operator ++() {
        ++i_;
        next();
        return *static_cast<Delegate*>(this);
      }
      bool operator == (const Delegate& rhs) const { return i_ == rhs.i_; }
      bool operator != (const Delegate& rhs) const { return i_ != rhs.i_; }
      Entity operator * () { return Entity(manager_, manager_->create_id(i_)); }
      const Entity operator * () const { return Entity(manager_, manager_->create_id(i_)); }

     protected:
      ViewIterator(EntityManager *manager, uint index)
          : manager_(manager), i_(index), capacity_(manager_->capacity()), free_cursor_(~0UL) {
        if (All) {
          std::sort(manager_->mFreeList.begin(), manager_->mFreeList.end());
          free_cursor_ = 0;
        }
      }
      ViewIterator(EntityManager *manager, const ComponentMask mask, uint index)
          : manager_(manager), mask_(mask), i_(index), capacity_(manager_->capacity()), free_cursor_(~0UL) {
        if (All) {
          std::sort(manager_->mFreeList.begin(), manager_->mFreeList.end());
          free_cursor_ = 0;
        }
      }

      void next() {
        while (i_ < capacity_ && !predicate()) {
          ++i_;
        }

        if (i_ < capacity_) {
          Entity entity = manager_->get(manager_->create_id(i_));
          static_cast<Delegate*>(this)->next_entity(entity);
        }
      }

      inline bool predicate() {
        return (All && valid_entity()) || (manager_->mEntityComponentMask[i_] & mask_) == mask_;
      }

      inline bool valid_entity() {
        const std::vector<uint> &free_list = manager_->mFreeList;
        if (free_cursor_ < free_list.size() && free_list[free_cursor_] == i_) {
          ++free_cursor_;
          return false;
        }
        return true;
      }

      EntityManager *manager_;
      ComponentMask mask_;
      uint i_;
      size_t capacity_;
      size_t free_cursor_;
    };

    class BaseView(bool All)
    {
    public:
      class Iterator : public ViewIterator<Iterator, All> {
      public:
        Iterator(EntityManager *manager,
          const ComponentMask mask,
          uint index) : ViewIterator<Iterator, All>(manager, mask, index) {
          ViewIterator<Iterator, All>::next();
        }

        void next_entity(Entity &entity) {}
      };


      Iterator begin() { return Iterator(manager_, mask_, 0); }
      Iterator end() { return Iterator(manager_, mask_, uint(manager_->capacity())); }
      const Iterator begin() const { return Iterator(manager_, mask_, 0); }
      const Iterator end() const { return Iterator(manager_, mask_, manager_->capacity()); }

    private:
      friend class EntityManager;

      explicit BaseView(EntityManager *manager) : manager_(manager) { mask_.set(); }
      BaseView(EntityManager *manager, ComponentMask mask) :
          manager_(manager), mask_(mask) {}

      EntityManager *manager_;
      ComponentMask mask_;
    };

  alias View = BaseView!(false);
  alias DebugView = BaseView!(true);

  template <typename ... Components>
  class UnpackingView {
   public:
    struct Unpacker {
      explicit Unpacker(ComponentHandle<Components> & ... handles) :
          handles(std::tuple<ComponentHandle<Components> & ...>(handles...)) {}

      void unpack(entityx::Entity &entity) const {
        unpack_<0, Components...>(entity);
      }

    private:
      template <int N, typename C>
      void unpack_(entityx::Entity &entity) const {
        std::get<N>(handles) = entity.component<C>();
      }

      template <int N, typename C0, typename C1, typename ... Cn>
      void unpack_(entityx::Entity &entity) const {
        std::get<N>(handles) = entity.component<C0>();
        unpack_<N + 1, C1, Cn...>(entity);
      }

      std::tuple<ComponentHandle<Components> & ...> handles;
    };


    class Iterator : public ViewIterator<Iterator> {
    public:
      Iterator(EntityManager *manager,
        const ComponentMask mask,
        uint index,
        const Unpacker &unpacker) : ViewIterator<Iterator>(manager, mask, index), unpacker_(unpacker) {
        ViewIterator<Iterator>::next();
      }

      void next_entity(Entity &entity) {
        unpacker_.unpack(entity);
      }

    private:
      const Unpacker &unpacker_;
    };


    Iterator begin() { return Iterator(manager_, mask_, 0, unpacker_); }
    Iterator end() { return Iterator(manager_, mask_, manager_->capacity(), unpacker_); }
    const Iterator begin() const { return Iterator(manager_, mask_, 0, unpacker_); }
    const Iterator end() const { return Iterator(manager_, mask_, manager_->capacity(), unpacker_); }


   private:
    friend class EntityManager;

    UnpackingView(EntityManager *manager, ComponentMask mask, ComponentHandle<Components> & ... handles) :
        manager_(manager), mask_(mask), unpacker_(handles...) {}

    EntityManager *manager_;
    ComponentMask mask_;
    Unpacker unpacker_;
  };+/

    /**
     * Number of managed entities.
     */
    size_t size() @property
    {
        return mEntityComponentMask.length - mFreeIds.length;
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
        return id.index < mEntityVersions.length &&
               mEntityVersions[id.index] == id.versionId;
    }

    /**
     * Create a new Entity.Id.
     *
     * Emits EntityCreatedEvent.
     */
    Entity create()
    {
        uint index, versionId;

        if (mFreeList.empty)
        {
            index = mIndexCounter;
            mIndexCounter++;
            accomodateEntity(index);
            versionId = mEntityVersions[index] = 1;
        }
        else
        {
            index = mFreeIds.front;
            mFreeIds.removeFront();
            versionId = mEntityVersions[index];
        }
        Entity entity = Entity(this, Entity.Id(index, versionId));
        //todo ?
        //mEventManager.emit!(EntityCreatedEvent)(entity);
        return entity;
    }

    /**
     * Destroy an existing Entity.Id and its associated Components.
     *
     * Emits EntityDestroyedEvent.
     */
    void destroy(Entity.Id entityId)
    {
        assertValid(entityId);

        uint index = entityId.index;

        //auto mask = mEntityComponentMask[entityId.index()];
        //todo ?
        //mEventManager.emit!(EntityDestroyedEvent)(Entity(this, entityId));

        // todo for each component, call component destructors
        // assuming components are classes, not struct
        /*foreach (pool; mComponentPools)
        {
            if (pool && mask.test(i))
                pool.destroy(index);
        }*/

        // reset all components for that entity
        mEntityComponentMask[index].reset();
        // invalidate its version, incrementing it
        mEntityVersions[index]++;
        mFreeList.insertFront(index);
    }

    Entity get(Entity.Id id)
    {
        assertValid(id);
        return Entity(this, id);
    }

    /**
     * Assign a Component to an Entity.Id, passing through Component constructor arguments.
     *
     *     Position &position = em.assign<Position>(e, x, y);
     *
     * @returns Smart pointer to newly created component.
     */
    C* assign(C, Args...)(Entity entity, Args args)
    {
        assertValid(entity.id);
        const BaseComponent.Family family = componentFamily!(C)();
        assert(!mEntityComponentMask[id.uniqueId][family]);

        // Placement new into the component pool.
        Pool!(C) *pool = accomodateComponent!(C)();

        //todo allocate new component in the pool
        //new(pool.get(id.index)) C(args);

        // Set the bit for this component.
        mEntityComponentMask[id.index].set(family);

        // Create and return handle.
        auto component = ComponentHandle!(C)(this, id);
        mEventManager.emit!(ComponentAddedEvent!(C))(Entity(this, id), component);
        return component;
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
        const uint index = id.index;

        // Find the pool for this component family.
        BasePool *pool = mComponentPools[family];
        auto component = ComponentHandle!(C)(this, id);
        mEventManager.emit!(ComponentRemovedEvent!(C))(Entity(this, id), component);

        // Remove component bit.
        mEntityComponentMask[id.index()].reset(family);

        // Call destructor.
        pool.destroy(index);
    }

    /**
     * Check if an Entity has a component.
     */
    bool hasComponent(C)(Entity.Id id)
    {
        assertValid(id);
        size_t family = componentFamily!(C)();

        // We don't bother checking the component mask, as we return a nullptr anyway.
        if (family >= mComponentPools.size())
            return false;

        BasePool *pool = mComponentPools[family];
        if (pool !is null || !mEntityComponentMask[id.index][family])
            return false;

        return true;
    }

    /**
     * Retrieve a Component assigned to an Entity.Id.
     *
     * @returns Pointer to an instance of C, or nullptr if the Entity.Id does not have that Component.
     */
    ComponentHandle!(C) component(Entity.Id id)
    {
        assertValid(id);
        BaseComponent.Family family = componentFamily!(C)();

        // We don't bother checking the component mask, as we return a nullptr anyway.
        if (family >= mComponentPools.size())
            return ComponentHandle!(C)();

        Pool *pool = &mComponentPools[family];
        if (!mEntityComponentMask[id.index()][family])
            return ComponentHandle!(C)();

        return new ComponentHandle!(C)(this, id);
    }

    /**
     * Retrieve a Component assigned to an Entity.Id.
     *
     * @returns Component instance, or nullptr if the Entity.Id does not have that Component.
     */
    //template <typename C, typename = typename std::enable_if<std::is_const<C>::value>::type>
    /*const ComponentHandle!(C, const EntityManager) component(Entity.Id id)
    {
        assertValid(id);
        size_t family = componentFamily!(C)();

        // We don't bother checking the component mask, as we return a nullptr anyway.
        if (family >= mComponentPools.size())
            return ComponentHandle!(C, const EntityManager)();

        BasePool *pool = mComponentPools[family];
        if (!pool || !mEntityComponentMask[id.index()][family])
            return ComponentHandle!(C, const EntityManager)();

        return ComponentHandle!(C, const EntityManager)(this, id);
    }*/

    /* todo use TypeTuple
    template <typename ... Components>
    std::tuple<ComponentHandle<Components>...> components(Entity.Id id) {
        return std::make_tuple(component<Components>(id)...);
    }

    template <typename ... Components>
    std::tuple<ComponentHandle<const Components, const EntityManager>...> components(Entity.Id id) const {
        return std::make_tuple(component<const Components>(id)...);
    }*/

    /**
     * Find Entities that have all of the specified Components.
     *
     * @code
     * for (Entity entity : entity_manager.entities_with_components<Position, Direction>()) {
     *   ComponentHandle<Position> position = entity.component<Position>();
     *   ComponentHandle<Direction> direction = entity.component<Direction>();
     *
     *   ...
     * }
     * @endcode
     */
    /*template <typename ... Components>
    View entities_with_components() {
      auto mask = component_mask<Components ...>();
      return View(this, mask);
    }*/

    /**
     * Find Entities that have all of the specified Components and assign them
     * to the given parameters.
     *
     * @code
     * ComponentHandle<Position> position;
     * ComponentHandle<Direction> direction;
     * for (Entity entity : entity_manager.entities_with_components(position, direction)) {
     *   // Use position and component here.
     * }
     * @endcode
     */
    /*template <typename ... Components>
    UnpackingView<Components...> entities_with_components(ComponentHandle<Components> & ... components) {
      auto mask = component_mask<Components...>();
      return UnpackingView<Components...>(this, mask, components...);
    }*/

    /**
     * Iterate over all *valid* entities (ie. not in the free list). Not fast,
     * so should only be used for debugging.
     *
     * @code
     * for (Entity entity : entity_manager.entities_for_debugging()) {}
     *
     * @return An iterator view over all valid entities.
     */
    /*DebugView entities_for_debugging() {
      return DebugView(this);
    }*/

    /+void unpack(C)(Entity.Id id, ComponentHandle!(C) a)
    {
        assertValid(id);
        a = component!(C)(id);
    }

    /**
     * Unpack components directly into pointers.
     *
     * Components missing from the entity will be set to nullptr.
     *
     * Useful for fast bulk iterations.
     *
     * ComponentHandle<Position> p;
     * ComponentHandle<Direction> d;
     * unpack<Position, Direction>(e, p, d);
     */
    void unpack(C, Args...)(Entity.Id id, ComponentHandle!(C) a, Args args)
    {
      assertValid(id);
      a = component!(C)(id);
      unpack!(Args)(id, args);
    }+/

    /**
     * Destroy all entities and reset the EntityManager.
     */
    //void reset();

private:
    void assertValid(Entity.Id id)
    {
        assert(id.index() < mEntityComponentMask.size(), "Entity.Id ID outside entity vector range");
        assert(mEntityVersions[id.index] == id.versionId, "Attempt to access Entity via an obsolete Entity.Id");
    }

    C *getComponentPtr(C)(Entity.Id id)
    {
        assert(valid(id));
        BasePool *pool = mComponentPools[componentFamily!(C)()];
        assert(pool);
        return cast(C*)(pool.get(id.index));
    }

    auto componentMask(Entity.Id id)
    {
        assertValid(id);
        return mEntityComponentMask.at(id.index);
    }

    auto componentMask(C)()
    {
        ComponentMask mask;
        mask.set(componentFamily!(C)());
        return mask;
    }

    BaseComponent.Family componentFamily(C)()
    {
        return Component!(C).family();
    }


/*    template <typename C1, typename C2, typename ... Components>
    ComponentMask component_mask() {
      return component_mask<C1>() | component_mask<C2, Components ...>();
    }

    template <typename C1, typename ... Components>
    ComponentMask component_mask(const ComponentHandle<C1> &c1, const ComponentHandle<Components> &... args) {
      return component_mask<C1, Components ...>();
    }*/

    void accomodateEntity()
    {
        if (mEntityComponentMask.length < mIndexCounter)
        {
            mEntityComponentMask.length = mIndexCounter;
            mEntityVersions.length = mIndexCounter;
            foreach (pool; mComponentPools.data)
                pool.accomodate(mIndexCounter);
        }
    }

    Pool!(C)* accomodateComponent(C)()
    {
        BaseComponent.Family family = componentFamily!(C)();

        if (mComponentPools.length <= family)
            mComponentPools.length = family + 1;

        mComponentPools[family].accomodate = pool;
        return cast(Pool!(C)*)mComponentPools[family];
    }


    // Current number of Entities
    uint            mIndexCounter = 0;
    // Event Manager
    EventManager    mEventManager;
    // Array of pools for each component family
    Pool[]          mComponentPools;
    // Bitmask of components for each entities.
    // Index into the vector is the Entity.Id.
    ComponentMask[] mEntityComponentMask;
    // Vector of entity version id's
    // Incremented each time an entity is destroyed
    uint[]          mEntityVersions;
    // List of available entity id's.
    SList!uint      mFreeIds;
}
