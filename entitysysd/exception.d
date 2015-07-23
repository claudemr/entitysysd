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

module entitysysd.exception;

public import std.exception;

class EntityException : Exception
{
    this(string msg, string file = null, size_t line = 0) @safe pure nothrow
    {
        super(msg, file, line);
    }
}

class ComponentException : Exception
{
    this(string msg, string file = null, size_t line = 0) @safe pure nothrow
    {
        super(msg, file, line);
    }
}

class EventException : Exception
{
    this(string msg, string file = null, size_t line = 0) @safe pure nothrow
    {
        super(msg, file, line);
    }
}

class SystemException : Exception
{
    this(string msg, string file = null, size_t line = 0) @safe pure nothrow
    {
        super(msg, file, line);
    }
}
