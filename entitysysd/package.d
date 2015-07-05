module entitysysd;

import entitysysd.entity;
import entitysysd.event;
import entitysysd.system;

class EntitySysD(uint MaxComponent)
{
    this()
    {
        events   = new EventManager;
        entities = new EntityManager!(MaxComponent)(events);
        systems  = new SystemManager(entities, events);
    }

    EventManager                 events;
    EntityManager!(MaxComponent) entities;
    SystemManager                systems;
}
