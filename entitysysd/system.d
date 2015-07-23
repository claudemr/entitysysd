/**
System management module.

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

module entitysysd.system;

public import core.time;
import std.algorithm;
import std.container;
import std.range;

import entitysysd.entity;
import entitysysd.event;
import entitysysd.exception;


/**
 * System interface. System class has to derive it and implement run.
 */
interface System
{
    /**
     * Called by the system-manager anytime its method run is called.
     */
    void run(EntityManager entities, EventManager events, Duration dt);
}


/**
 * Entry point for systems. Allow to register systems.
 */
class SystemManager
{
public:
    this(EntityManager entityManager,
         EventManager  eventManager)
    {
        mEntityManager = entityManager;
        mEventManager  = eventManager;
    }

    /**
     * Register a new system.
     *
     * Throws: SystemException if the system was already registered.
     */
    void register(System system)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(sysNode.empty);
        mSystems ~= system;
    }

    /**
     * Unregister a system.
     *
     * Throws: SystemException if the system was not registered.
     */
    void unregister(System system)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(!sysNode.empty);
        mSystems.linearRemove(sysNode.take(1));
    }

    /**
     * Run all the registered systems.
     *
     * They are runt in the order that they were registered.
     */
    void run(Duration dt)
    {
        foreach (s; mSystems)
            s.run(mEntityManager, mEventManager, dt);
    }

private:
    EntityManager mEntityManager;
    EventManager  mEventManager;
    DList!System  mSystems;
}
