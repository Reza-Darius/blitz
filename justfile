SERVER_BIN := "/zig-out/bin/blitz-server"
CLIENT_BIN := "/zig-out/bin/blitz-client"
SERVER_ADDR := "127.0.0.1:4000"

build:
  zig build

server: build
  .{{ SERVER_BIN }} {{ SERVER_ADDR }}

client: build
  .{{ CLIENT_BIN }} {{ SERVER_ADDR }}

clean:
  rm -rf .zig-cache
