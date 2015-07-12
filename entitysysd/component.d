module entitysysd.component;

import entitysysd.entity;
import entitysysd.event;


struct ComponentHandle(C, EM = EntityManager)
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

struct BaseComponent
{
    alias Family = size_t;
    static Family familyCounter = 0;
}

struct Component(Derived)
{
public:
    //alias Handle = ComponentHandle!(Derived);
    //alias ConstHandle = ComponentHandle!(const Derived, const EntityManager);

    static BaseComponent.Family family()
    {
        static BaseComponent.Family family = -1;
        if (family == -1)
        {
            family = mBaseComponent.familyCounter;
            mBaseComponent.familyCounter++;
        }

        return family;
    }

private:
    BaseComponent mBaseComponent;
};

/+
/**
 * Emitted when any component is inserted to an entity.
 */
class ComponentInsertedEvent : Event!(ComponentInsertedEvent)
{
    this(Entity lEntity)
    {
        entity = lEntity;
    }

    Entity entity;
}

/**
 * Emitted when any component is removed from an entity.
 */
class ComponentRemovedEvent(C) : Event!(ComponentRemovedEvent)
{
    this(Entity lEntity)
    {
        entity = lEntity;
    }

    Entity entity;
}
+/
