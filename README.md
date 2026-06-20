# Blitz

An easy to use in-memory key value store inspired by Redis!

Currently only supports x86-64 Linux systems.

## Hello World

```bash
# build from source
$ git clone "https://github.com/Reza-Darius/blitz" blitz
$ cd blitz
$ zig build
$ cd zig-out/bin

# setup a listening server
$ ./blitz-cli -s 127.0.0.4:3000

# in another terminal
$ ./blitz-cli -c 127.0.0.4:3000 set hello 42
version=.V1, Response: .Ok, paylen=0

$ ./blitz-cli -c 127.0.0.4:3000 get hello
version=.V1, Response: .Ok, paylen=9, Integer: 42
```

Supported operations:

`GET [key]`, retrieves a value from the store

`SET [key] [value]`, sets a value inside the store (will overwrite existing entries)

`DEL [key]`, deletes an entry if it exists

Supported data types for keys and values:

```
boolean: true/false
64 bit signed integer: 42
64 bit precision floats: 1.825
ascii encoded strings: hello
```

## Implementation details

- asynchronous event loop based on `epoll()`
- state machine based request response model
- use of Zig's compile time reflection for reliable parsing
- efficient allocation patterns through the use of arenas
- binary serialization protocol
- hand rolled hashtable with open addressing and robin hood hashing
- zero dependencies
