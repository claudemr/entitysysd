/**
Component facilities module.

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

module entitysysd.component;

// UDA for component types
enum component;

template isComponent(C)
{
    import std.typetuple : anySatisfy;
        import std.traits : isIntegral;

    enum bool isComponentAttr(D) = is(D == component);
    static if (__traits(compiles, __traits(getAttributes, C)))
        enum bool isComponent = anySatisfy!(isComponentAttr,
                                            __traits(getAttributes, C)) &&
                                (is(C == struct) || is(C == union));
    else
        enum bool isComponent = false;
}

template areComponents(CList...)
{
    import std.typetuple : allSatisfy;
    enum bool areComponents = allSatisfy!(isComponent, CList);
}


struct BaseComponentCounter
{
    static size_t counter = 0;
}

struct ComponentCounter(Derived)
{
public:
    static size_t getId()
    {
        static size_t counter = -1;
        if (counter == -1)
        {
            counter = mBaseComponentCounter.counter;
            mBaseComponentCounter.counter++;
        }

        return counter;
    }

private:
    BaseComponentCounter mBaseComponentCounter;
}

//******************************************************************************
//***** UNIT-TESTS
//******************************************************************************

///
unittest
{
    @component struct TestComponent0
    {
        int a, b;
    }

    @component class TestComponent1 // component cannot be a class
    {
        string str;
    }

    @component union TestComponent2
    {
        float f;
        uint  u;
    }

    static assert(!isComponent!int);
    static assert(isComponent!TestComponent0);
    static assert(!isComponent!TestComponent1);
    static assert(isComponent!TestComponent2);
}