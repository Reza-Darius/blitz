# Blitz
A fast in-memory key value store inspired by Redis!

## Implementation details

- GET, SET, DEL commands for a variety of data types
- asynchronous event loop based on `epoll()`
- state machine based request response model
- use of Zig's compile time reflection for reliable parsing
- efficient allocation patterns through the use of arenas
- binary serialization protocol
- hand rolled hashtable with open addressing with robin hood hashing
- zero dependencies outside the standard library
