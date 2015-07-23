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

module entitysysd.system;

public import core.time;
import std.algorithm;
import std.container;
import std.range;

import entitysysd.entity;
import entitysysd.event;
import entitysysd.exception;


/**
 * System interface.
 */
interface System
{
    void run(EntityManager entities, EventManager events, Duration dt);
}


class SystemManager
{
public:
    this(EntityManager entityManager,
         EventManager  eventManager)
    {
        mEntityManager = entityManager;
        mEventManager  = eventManager;
    }

    void register(System system)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(sysNode.empty);
        mSystems ~= system;
    }

    void unregister(System system)
    {
        auto sysNode = mSystems[].find(system);
        enforce!SystemException(!sysNode.empty);
        mSystems.linearRemove(sysNode.take(1));
    }

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
