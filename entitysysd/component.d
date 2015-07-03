module entitysysd.component;

import entitysysd.entity;


class ComponentHandle(C, EM = EntityManager)
{
public:
    alias ComponentType = C;

    bool valid()
    {
        return (mManager !is null)   &&
               (mManager.valid(mId)) &&
               (mManager.hasComponent!(C)(mId));
    }

    /+
    template <typename C, typename EM>
    inline ComponentHandle<C, EM>::operator bool() const {
      return valid();
    }

    template <typename C, typename EM>
    inline C *ComponentHandle<C, EM>::operator -> () {
      assert(valid());
      return manager_->template get_component_ptr<C>(id_);
    }

    template <typename C, typename EM>
    inline const C *ComponentHandle<C, EM>::operator -> () const {
      assert(valid());
      return manager_->template get_component_ptr<C>(id_);
    }+/


    C* get()
    {
        assert(valid());
        return mManager.getComponentPtr!(C)(mId);
    }

    /+template <typename C, typename EM>
    inline const C *ComponentHandle<C, EM>::get() const {
      assert(valid());
      return manager_->template get_component_ptr<C>(id_);
    }+/

    void remove()
    {
        assert(valid());
        mManager.remove!(C)(mId);
    }

    /*bool operator == (const ComponentHandle<C> &other) const {
        return manager_ == other.manager_ && id_ == other.id_;
    }

    bool operator != (const ComponentHandle<C> &other) const {
        return !(*this == other);
    }*/

private:
    this(EM *manager, Entity.Id id)
    {
        mManager = manager;
        mId = id;
    }

    EM        mManager;
    Entity.Id mId;
}


/**
 * Base component class, only used for insertion into collections.
 *
 * Family is used for registration.
 */
struct BaseComponent
{
public:
    alias Family = size_t;

protected:
    static Family mFamilyCounter = 0;
}


/**
 * Component implementations should inherit from this.
 *
 * Components MUST provide a no-argument constructor.
 * Components SHOULD provide convenience constructors for initializing on assignment to an Entity::Id.
 *
 * This is a struct to imply that components should be data-only.
 *
 * Usage:
 *
 *     struct Position : public Component<Position> {
 *       Position(float x = 0.0f, float y = 0.0f) : x(x), y(y) {}
 *
 *       float x, y;
 *     };
 *
 * family() is used for registration.
 */
struct Component(Derived)
{
public:
    alias baseComponent this;

    BaseComponent baseComponent;
    alias Handle = ComponentHandle!(Derived);
    alias ConstHandle = ComponentHandle!(const Derived, const EntityManager);

private:
    static Family family()
    {
        static Family family = mFamilyCounter;
        mFamilyCounter++;
        //todo assert(family < entityx::MAX_COMPONENTS);
        return family;
    }
};


/**
 * Emitted when any component is added to an entity.
 */
struct ComponentAddedEvent(C)
{
    alias event this;

    this(Entity lEntity)
    {
        entity = lEntity;
    }

    Entity entity;
    Event!(ComponentAddedEvent!(C)) event;
}

/**
 * Emitted when any component is removed from an entity.
 */
struct ComponentRemovedEvent(C)
{
    alias event this;

    this(Entity lEntity)
    {
        entity = lEntity;
    }

    Entity entity;
    Event!(ComponentRemovedEvent!(C)) event;
}

