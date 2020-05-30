# Migration Guide from saschatimme Elm 0.18 library

## Phoenix.push
The signature has changed from:
```elm
push : String -> Push msg -> Cmd msg
```
to
```elm
push : Socket msg -> Push msg -> Cmd msg
```

This now takes the `Socket` as a parameter instead of the `endpoint` string.

Why? - The push needs access to the parent `Msg` which is stored in the `Socket` config.

Before
```elm
  Phoenix.push "/websocket" myPush
```
to
```elm
  let socket = Phoenix.Socket.init "/websocket" PhoenixMsg
  in
  Phoenix.push socket myPush
```

## Javascript
- add call to init
- Remove /websocket from end of endpoint as Phoenix JS adds this itself

## Not yet implemented

```
Channel.onDisconnect
Channel.onLeave
Channel.onLeaveError
Channel.onRejoin
Channel.onRequestJoin

Socket.heartbeatIntervallSeconds (with typo)
Socket.onAbnormalClose
Socket.onClose
Socket.onNormalClose
Socket.onOpen
Socket.reconnectTimer
Socket.withoutHeartbeat
```
These functions still exist in the code but are not exposed as they have no effect
so if you try to use them you will get compilation errors

Additionally `Presence` is not implemented
