module entitysysd.bitarray;

struct BitArray(size_t NbBits = 64)
{
    ulong[(NbBits + 63) / 64] data;

    int opIndex(size_t i)
    {
        assert(i < NbBits);
        size_t offset = i >> 6;
        size_t shift  = i & 63;

        return (data[offset] >> shift) & 0x1;
    }

    int opIndexAssign(int b, size_t i)
    {
        assert(i < NbBits);
        size_t offset = i >> 6;
        size_t shift  = i & 63;

        if (b)
            data[offset] |= 0x1UL << shift;
        else
            data[offset] &= ~(0x1UL << shift);

        return b;
    }

    void reset()
    {
        foreach (ref elem; data)
            elem = 0;
    }
}


unittest
{
    //dmd -main -unittest entitysysd/bitarray.d
    BitArray!(100) bitArray;

    assert(bitArray.data.length == 2);
    assert(bitArray.data.sizeof == 8*2);

    for (int i = 0; i < 100; i++)
        assert(bitArray[i] == 0);

    for (int i = 0; i < 50; i++)
        bitArray[i*2] = 1;
    for (int i = 0; i < 100; i++)
        assert(bitArray[i] == !(i & 0x1));
}