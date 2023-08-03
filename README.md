#  SimpleChat

A simple chat made to play with [Distributed actors](https://www.swift.org/blog/distributed-actors/).

## Run
Just run SimpleChat destination in Xcode or simply `swift run` in terminal.

To start chatting:

1. Create room:
```
curl -d '{"name":"Test"}' -H "Content-Type: application/json" -X POST http://localhost:8080/room
```
or 
```
curl -d '{"name":"Test", "id":"Some pregenerated UUID"}' -H "Content-Type: application/json" -X POST http://localhost:8080/room
```

it will return you a room info with a/the UUID.

2. Create user:
```
curl -d '{"name":"Test"}' -H "Content-Type: application/json" -X POST http://localhost:8080/user
```
or 
```
curl -d '{"name":"Test", "id":"Some pregenerated UUID"}' -H "Content-Type: application/json" -X POST http://localhost:8080/yser
```

it will return you a user info with a/the UUID.

3. Connect to the room with provided room id and user id `'ws://localhost:8080/chat?room_id=room_UUID&user_id=user_UUID'` and start chating.

## TODO:
1. Check if actors are cleaned from memory when websocket disconnects.
2. Event sourcing with proper database.
3. Clustering with fault tolerance. Check different scenarios like room node crashes and etc.
