#  swift-chat

A simple chat made to play with [Distributed actors](https://www.swift.org/blog/distributed-actors/).

## Run

Swift 5.9 is needed (was playing with new Swift Foundations).

1. Install `brew install postgresql`

2. Open `App/swift-chat.xcodeproj`

3. Configure scheme environment to run a database (DB_USERNAME, DB_PASSWORD and DB_NAME)

4. Run `Server` either through Xcode schemes or using command line tools. You need to provide info on which node and where you want to start, e.g. `main/room/database --host 127.0.0.1 --port 2551`. 
  Additionaly you can start a seperate `Room` and `Database` to play.

5. Open `swift-chat` app on device/simulator. Create user and room name, and connect. Open another instance on different device/simulator and connect to the room by entering same name.

## TODO:
1. ~~Check if actors are cleaned from memory when websocket disconnects.~~
2. ~~Some database with simple event sourcing.~~
3. ~~Basic clustering with fault tolerance. Check different scenarios like room node crashes and etc.~~
4. Testing.
5. Tracing.
6. Improve scalibility and fault tolerance.
7. TBD
