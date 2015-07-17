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

module entitysysd.component;

// UDA for component types
enum component;


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

version(unittest)
{
    @component alias TestComponent0 = float;

    @component struct TestComponent1
    {
        int a, b;
    }

    @component class TestComponent2
    {
        string str;
    }
}