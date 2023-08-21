#  swift-chat

A simple chat made to play with [Distributed actors](https://www.swift.org/blog/distributed-actors/).

## Run

1. Open `App/swift-chat.xcodeproj`

2. Run `Server` scheme.

3. Open `swift-chat` app on device/simulator. Create user and room name, and connect. Open another instance on different device/simulator and connect to the room by entering same name.

## TODO:
1. ~~Check if actors are cleaned from memory when websocket disconnects.~~
2. Event sourcing with proper database.
3. Clustering with fault tolerance. Check different scenarios like room node crashes and etc.
