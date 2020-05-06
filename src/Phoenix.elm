module Phoenix exposing (connect, new, push, update)

import Dict
import Json.Decode as JD
import Json.Encode as JE
import Phoenix.Channel exposing (Channel)
import Phoenix.ChannelStates as ChannelStates
import Phoenix.Ports as Ports
import Phoenix.Push exposing (Push)
import Phoenix.Socket exposing (Socket)
import Phoenix.Types exposing (..)
import Task
import Time


-- Based on: https://sascha.timme.xyz/elm-phoenix/
-- Code:  https://github.com/saschatimme/elm-phoenix


new : Model msg
new =
    { socketState = Disconnected, channelStates = ChannelStates.new, pushRef = 0, pushes = Dict.empty }


push : String -> (Msg msg -> msg) -> Push msg -> Cmd msg
push endpoint parentMsg p =
    Cmd.map parentMsg <|
        Task.perform (\_ -> SendPush p) (Task.succeed Ok)


update : Socket msg -> List (Channel msg) -> Msg msg -> Model msg -> ( Model msg, Cmd msg, Maybe msg )
update socket channels msg model =
    let
        _ =
            if socket.debug then
                Debug.log "msg model" ( msg, model )
            else
                ( msg, model )
    in
    case msg of
        NoOp ->
            ( model, Cmd.none, Nothing )

        Tick _ ->
            case model.socketState of
                Disconnected ->
                    ( { model | socketState = Connected }
                    , Ports.connectSocket
                        { endpoint = socket.endpoint
                        , params = JE.object <| List.map (\( k, v ) -> ( k, JE.string v )) socket.params -- Elm 0.19 JE.dict identity JE.string (Dict.fromList socket.params)
                        }
                    , Nothing
                    )

                Connected ->
                    let
                        ( updatedChannelStates, newChannels, removedChannelObjs ) =
                            ChannelStates.update channels model.channelStates

                        cmds =
                            List.map (\c -> Ports.joinChannel { topic = c.topic, payload = Maybe.withDefault JE.null c.payload }) newChannels
                                ++ List.map Ports.leaveChannel removedChannelObjs
                    in
                    ( { model | channelStates = updatedChannelStates }, Cmd.batch cmds, Nothing )

        SendPush p ->
            ( { model
                | pushes = Dict.insert model.pushRef p model.pushes
                , pushRef = model.pushRef + 1
              }
            , Ports.push { ref = model.pushRef, topic = p.topic, event = p.event, payload = p.payload }
            , Nothing
            )

        ChannelPushOk topic pushRef payload ->
            case Dict.get pushRef model.pushes of
                Nothing ->
                    ( model, Cmd.none, Nothing )

                Just p ->
                    ( { model | pushes = Dict.remove pushRef model.pushes }, Cmd.none, Maybe.map (\c -> c payload) p.onOk )

        ChannelPushError topic pushRef payload ->
            case Dict.get pushRef model.pushes of
                Nothing ->
                    ( model, Cmd.none, Nothing )

                Just p ->
                    ( { model | pushes = Dict.remove pushRef model.pushes }, Cmd.none, Maybe.map (\c -> c payload) p.onError )

        ChannelCreated topic channelObj ->
            ( { model | channelStates = ChannelStates.setCreated topic channelObj model.channelStates }
            , Cmd.none
            , Nothing
            )

        ChannelJoinOk topic payload ->
            case List.filter (\c -> c.topic == topic) channels of
                [ channel ] ->
                    case channel.onJoin of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onJoinMsg ->
                            ( model, Cmd.none, Just (onJoinMsg payload) )

                _ ->
                    ( model, Cmd.none, Nothing )

        ChannelJoinError topic payload ->
            case List.filter (\c -> c.topic == topic) channels of
                [ channel ] ->
                    case channel.onJoinError of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onJoinError ->
                            ( model, Cmd.none, Just (onJoinError payload) )

                _ ->
                    ( model, Cmd.none, Nothing )

        ChannelLeaveOk topic payload ->
            case List.filter (\c -> c.topic == topic) channels of
                [ channel ] ->
                    case channel.onLeave of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onLeaveMsg ->
                            ( model, Cmd.none, Just (onLeaveMsg payload) )

                _ ->
                    ( model, Cmd.none, Nothing )

        ChannelLeaveError topic payload ->
            case List.filter (\c -> c.topic == topic) channels of
                [ channel ] ->
                    case channel.onLeaveError of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onLeaveError ->
                            ( model, Cmd.none, Just (onLeaveError payload) )

                _ ->
                    ( model, Cmd.none, Nothing )

        ChannelMessage topic event payload ->
            case List.filter (\c -> c.topic == topic) channels of
                [ channel ] ->
                    case Dict.get event channel.on of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onMsg ->
                            ( model, Cmd.none, Just (onMsg payload) )

                _ ->
                    ( model, Cmd.none, Nothing )


connect : Socket msg -> (Msg msg -> msg) -> List (Channel msg) -> Sub msg
connect socket parentMsg channels =
    let
        tickInterval =
            if socket.debug then
                1000
            else
                10
    in
    Sub.map parentMsg <|
        Sub.batch
            [ Ports.channelEvent parseChannelEvent
            , Time.every tickInterval Tick
            ]


parseChannelEvent : Ports.ChannelEvent -> Msg msg
parseChannelEvent ( eventName, topic, data ) =
    let
        decoder =
            case eventName of
                "message" ->
                    JD.map2
                        (ChannelMessage topic)
                        (JD.field "event" JD.string)
                        (JD.field "payload" JD.value)

                "created" ->
                    JD.map
                        (ChannelCreated topic)
                        (JD.field "channel" JD.value)

                "joinOk" ->
                    JD.map
                        (ChannelJoinOk topic)
                        (JD.field "payload" JD.value)

                "pushOk" ->
                    JD.field "type" JD.string
                        |> JD.andThen
                            (\pushType ->
                                case pushType of
                                    "join" ->
                                        JD.map
                                            (ChannelJoinOk topic)
                                            (JD.field "payload" JD.value)

                                    "leave" ->
                                        JD.map
                                            (ChannelLeaveOk topic)
                                            (JD.field "payload" JD.value)

                                    "msg" ->
                                        JD.map2
                                            (ChannelPushOk topic)
                                            (JD.field "ref" JD.int)
                                            (JD.field "payload" JD.value)

                                    _ ->
                                        JD.fail "Unnown push type"
                            )

                "pushError" ->
                    JD.field "type" JD.string
                        |> JD.andThen
                            (\pushType ->
                                case pushType of
                                    "join" ->
                                        JD.map
                                            (ChannelJoinError topic)
                                            (JD.field "payload" JD.value)

                                    "leave" ->
                                        JD.map
                                            (ChannelLeaveError topic)
                                            (JD.field "payload" JD.value)

                                    "msg" ->
                                        JD.map2
                                            (ChannelPushError topic)
                                            (JD.field "ref" JD.int)
                                            (JD.field "payload" JD.value)

                                    _ ->
                                        JD.fail "Unnown push type"
                            )

                _ ->
                    JD.fail "Unknown event"
    in
    case JD.decodeValue decoder data of
        Ok msg ->
            msg

        Err err ->
            let
                _ =
                    Debug.log "ChannelEvent parsing error : " ( eventName, topic, err )
            in
            NoOp
