module entitysysd.pool;


struct Pool(T, size_t ChunkSize = 8192)
{
public:
    void accomodate(in size_t nbElements)
    {
        while (nbElements > mMaxElements)
        {
            mNbChunks++;
            mMaxElements = (mNbChunks * ChunkSize) / T.sizeof;
        }

        if (mData.length != mNbChunks)
            mData.length = mNbChunks;
        mNbElements  = nbElements;
    }

    ref T opIndex(size_t n)
    {
        assert(n < mNbElements);
        return *getPtr(n);
    }

    T opIndexAssign(T t, size_t n)
    {
        assert(n < mNbElements);
        *getPtr(n) = t;
        return t;
    }

    T* getPtr(in size_t n)
    {
        if (n >= mNbElements)
            return null;
        size_t offset = n * T.sizeof;
        return cast(T*)&mData[offset / ChunkSize][offset % ChunkSize];
    }

    T* ptr() @property
    {
        return cast(T*)mData.ptr;
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
    size_t              mNbChunks;
    size_t              mMaxElements;
    size_t              mNbElements;
    ubyte[ChunkSize][]  mData;
}


//dmd -main -unittest entitysysd/pool.d
unittest
{
    static struct TestComponent
    {
        int    i;
        string s;
    }

    Pool!TestComponent pool0;
    Pool!ulong         pool1;

    assert(pool0.nbChunks == 0 && pool1.nbElements == 0);

    pool0.accomodate(5);
    pool1.accomodate(2000);

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