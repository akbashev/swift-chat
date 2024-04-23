#  swift-chat

A simple chat made to play with [Distributed actors](https://www.swift.org/blog/distributed-actors/).

## Run

Swift 5.9 is needed (was playing with new Swift Foundations, although removed in the end).

1. Install `brew install postgresql`

2. Open `App/swift-chat.xcodeproj`

3. Configure scheme environment for Frontend node to run a database (DB_USERNAME, DB_PASSWORD and DB_NAME)

4. Run `fronend` node either through Xcode schemes or using command line tools. You need to provide info on which node and where you want to start, e.g. `frontend --host 127.0.0.1 --port 2550`. 
  Additionaly you can start seperate `room` nodes to play:
  `room --host 127.0.0.1 --port 2551

5. Open `swift-chat` app on device/simulator. Create user and room name, and connect. Open another instance on different device/simulator and connect to the room by entering same name.

## TODO:
(no priorities, so no order)
* ~~Check if actors are cleaned from memory when websocket disconnects.~~
* ~~Some database with simple event sourcing.~~
* ~~Basic clustering with fault tolerance. Check different scenarios like room node crashes and etc.~~
* ~~DATABASE NODE FAILURES ARE NOT HANDLED AT THE MOMENT~~
* ~~Currently Event sourcing is not there yet and rudimentary (without state, recovery and snapshoting). Invest some time into this.~~
* Add some basic documentation.
* Testing—at least covering `Room`, `User` and `WebsocketConnection` actors would be nice.
* Tracing—debugging is quite hard thing even on a single node. Add [Swift Distributed Tracing](https://github.com/apple/swift-distributed-tracing)
* Interesting to play with [Swift OpenAPI generator](https://github.com/apple/swift-openapi-generator).
* Improve scalibility and fault tolerance:
  1. Add [node discovery](https://swiftpackageindex.com/apple/swift-distributed-actors/main/documentation/distributedcluster/clustering#Automatic-Node-Discovery) logic.
  2. Improve error handling. 
* Spining some example on real device/vps to get more info and for fun :)
* TBD
