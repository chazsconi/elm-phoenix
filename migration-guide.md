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
