module entitysysd.pool;

import std.array;

/**
 * Provides a resizable, semi-contiguous pool of memory for constructing
 * objects in. Pointers into the pool will be invalided only when the pool is
 * destroyed.
 *
 * The semi-contiguous nature aims to provide cache-friendly iteration.
 *
 * Lookups are O(1).
 * Appends are amortized O(1).
 */
class BasePool
{
public:
    this(size_t elementSize, size_t chunkSize = 8192)
    {
        mElementSize = elementSize;
        mChunkSize = chunkSize;
    }
    //virtual ~BasePool();

    size_t size() @property
    {
        return mSize;
    }

    size_t capacity() @property
    {
        return mCapacity;
    }

    size_t chunks() @property
    {
        return mBlocks.data.length;
    }

    /// Ensure at least n elements will fit in the pool.
    void expand(size_t n)
    {
        if (n >= mSize)
            if (n >= mCapacity)
            {
                reserve(n);
                mSize = n;
            }
    }

    void reserve(size_t n)
    {
        n = ((n  + mChunkSize - 1) / mChunkSize) * mChunkSize;
        mBlocks.reserve(mCapacity + n);
        mCapacity += n;
    }

    void *get(size_t n)
    {
        assert(n < mSize);
        return cast(void*)mBlocks.data[n / mChunkSize] + (n % mChunkSize) * mElementSize;
    }

    const(void*) get(size_t n)
    {
        assert(n < mSize);
        return cast(const(void*))mBlocks.data[n / mChunkSize] + (n % mChunkSize) * mElementSize;
    }

    void destroy(size_t n)
    {
    }

protected:
    Appender!(ubyte*[]) mBlocks;
    size_t mElementSize;
    size_t mChunkSize;
    size_t mSize;
    size_t mCapacity;
}


/**
 * Implementation of BasePool that provides type-"safe" deconstruction of
 * elements in the pool.
 */
class Pool(T, size_t ChunkSize = 8192) : BasePool
{
public:
    this()
    {
        super(sizeof(T), ChunkSize);
    }
    /*virtual ~Pool()
    {
        // Component destructors *must* be called by owner.
    }*/

    void destroy(size_t n)
    {
        assert(n < size_);
        /*T *ptr = static_cast<T*>(get(n));
        ptr->~T();*/
    }
}


unittest
{
}