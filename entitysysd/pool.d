/**
Memory pool for component storage.

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

module entitysysd.pool;


template hasConst(C)
{
    import std.typetuple : anySatisfy;
    import std.traits : RepresentationTypeTuple;

    enum bool isConst(F) = is(F == const);
    enum bool hasConst = anySatisfy!(isConst, RepresentationTypeTuple!C);
}

class BasePool
{
public:
    this(size_t elementSize, size_t chunkSize)
    {
        mElementSize = elementSize;
        mChunkSize   = chunkSize;
    }

    void accomodate(in size_t nbElements)
    {
        while (nbElements > mMaxElements)
        {
            mNbChunks++;
            mMaxElements = (mNbChunks * mChunkSize) / mElementSize;
        }

        if (mData.length != mNbChunks * mChunkSize)
            mData.length = mNbChunks * mChunkSize;
        mNbElements  = nbElements;
    }

    size_t nbElements() @property
    {
        return mNbElements;
    }

    size_t nbChunks() @property
    {
        return mNbChunks;
    }

private:
    size_t  mElementSize;
    size_t  mChunkSize;
    size_t  mNbChunks;
    size_t  mMaxElements;
    size_t  mNbElements;
    ubyte[] mData;
}

class Pool(T, size_t ChunkSize = 8192) : BasePool
{
    this(in size_t n)
    {
        super(T.sizeof, ChunkSize);
        accomodate(n);
    }

    ref T opIndex(size_t n)
    {
        return *getPtr(n);
    }

    static if (!hasConst!T)
    {
        T opIndexAssign(T t, size_t n)
        {
            *getPtr(n) = t;
            return t;
        }
    }

    void initN(size_t n)
    {
        import std.conv : emplace;
        emplace(getPtr(n));
    }

    T* getPtr(in size_t n)
    {
        if (n >= mNbElements)
            return null;
        size_t offset = n * mElementSize;
        return cast(T*)&mData[offset];
    }

    T* ptr() @property
    {
        return cast(T*)mData.ptr;
    }

}


//dmd -main -unittest entitysysd/pool.d
unittest
{
    static struct TestComponent
    {
        int    i;
        string s;
    }

    auto pool0 = new Pool!TestComponent(5);
    auto pool1 = new Pool!ulong(2000);

    assert(pool0.nbChunks == 1);
    assert(pool1.nbChunks == (2000 * ulong.sizeof + 8191) / 8192);
    assert(pool1.getPtr(1) !is null);
    assert(pool0.getPtr(5) is null);

    pool0[0].i = 10; pool0[0].s = "hello";
    pool0[3] = TestComponent(5, "world");

    assert(pool0[0].i == 10 && pool0[0].s == "hello");
    assert(pool0[1].i == 0  && pool0[1].s is null);
    assert(pool0[2].i == 0  && pool0[2].s is null);
    assert(pool0[3].i == 5  && pool0[3].s == "world");
    assert(pool0[4].i == 0  && pool0[4].s is null);

    pool1[1999] = 325;
    assert(pool1[1999] == 325);

}