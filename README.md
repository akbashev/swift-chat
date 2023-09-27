#  swift-chat

A simple chat made to play with [Distributed actors](https://www.swift.org/blog/distributed-actors/).

## Run

Swift 5.9 is needed (was playing with new Swift Foundations).

1. Open `App/swift-chat.xcodeproj`

2. Run `Server` scheme.

3. Open `swift-chat` app on device/simulator. Create user and room name, and connect. Open another instance on different device/simulator and connect to the room by entering same name.

## TODO:
1. ~~Check if actors are cleaned from memory when websocket disconnects.~~
2. ~~Some database with simple event sourcing.~~
3. Clustering with fault tolerance. Check different scenarios like room node crashes and etc.
4. TBD
