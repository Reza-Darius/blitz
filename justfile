BIN := "/zig-out/bin/blitz-cli"
SERVER_ADDR := "127.0.0.1:4000"

build:
  zig build

server: build
  .{{ BIN }} -s {{ SERVER_ADDR }}

cset: build
  .{{ BIN }} -c {{ SERVER_ADDR }} set hello 42

cget: build
  .{{ BIN }} -c {{ SERVER_ADDR }} get hello

cdel: build
  .{{ BIN }} -c {{ SERVER_ADDR }} del hello

clean:
  rm -rf .zig-cache

release:
  zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast --summary all
