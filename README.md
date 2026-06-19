# Blitz
A fast key value store inspired by Redis!!

## Implementation features

- GET, SET, DEL commands for a variety of data types
- asynchronous event loop based on `epoll()`
- state machine based request response model
- use of Zig's compile time reflection for reliable parsing
- thoughtful allocation patterns utilizing arenas for connection cycles
- binary serialization protocol
- hand rolled hashtable with open addressing (robin hood hashing)
- no dependencies outside the std library
