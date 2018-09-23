module ringbuffer;

struct RingBuffer(T)
{
    nothrow @nogc:
    import dplug.core.nogc : mallocSlice, freeSlice;
    
    T[] buffer;
    size_t readIndex;
    size_t writeIndex;
    alias buffer this;
    
    this(size_t length) nothrow @nogc
    {
        this.buffer = mallocSlice!T(length);
        this.buffer[] = 0;
        this.readIndex = 0;
        this.writeIndex = length / 2;
    }

    ~this() nothrow @nogc
    {
        freeSlice(this.buffer);
    }

    T front() pure nothrow @nogc
    {
        return this.buffer[this.readIndex];
    }

    void pushBack(T value) nothrow @nogc
    {
        this.buffer[this.writeIndex] = value;
        this.writeIndex = (this.writeIndex + 1) % this.length;
    }

    void popFront() nothrow @nogc
    {
        this.readIndex = (this.readIndex + 1) % this.length;
    }

    void setInterval(size_t i) nothrow @nogc
    {
        if (i < this.length) {
            this.writeIndex = (this.readIndex + i) % this.length;
        }
        this.buffer[] = 0;
    }
}

@system unittest
{
    auto buf = RingBuffer!float(3);
    assert(buf[] == [0.0, 0.0, 0.0]);
    buf.setInterval(2);
    assert(buf.readIndex == 0);
    assert(buf.writeIndex == 2);
    assert(buf.front == 0);
    buf.pushBack(1.0);
    buf.pushBack(2.0);
    buf.pushBack(3.0);
    assert(buf[] == [2.0, 3.0, 1.0]);
}
