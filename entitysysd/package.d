module entitysysd;

public import entitysysd.entity;
public import entitysysd.event;
public import entitysysd.system;

class EntitySysD
{
    this(size_t maxComponent = 64, size_t poolSize = 8192)
    {
        events   = new EventManager;
        entities = new EntityManager(events, maxComponent, poolSize);
        systems  = new SystemManager(entities, events);
    }

    EventManager  events;
    EntityManager entities;
    SystemManager systems;
}
