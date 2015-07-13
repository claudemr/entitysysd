module entitysysd.pool;

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
        assert(n < nbElements);
        return *getPtr(n);
    }

    T opIndexAssign(T t, size_t n)
    {
        assert(n < nbElements);
        *getPtr(n) = t;
        return t;
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