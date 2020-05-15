module Phoenix exposing (connect, mapMsg, new, push, update)

{-| Entrypoint for Phoenix


# Definition

@docs connect, new, push, update, mapMsg

-}

import Dict
import Json.Decode as JD
import Json.Encode as JE
import Phoenix.Channel exposing (Channel, Topic)
import Phoenix.ChannelStates as ChannelStates
import Phoenix.Ports as Ports
import Phoenix.Push exposing (Push)
import Phoenix.Socket exposing (Socket)
import Phoenix.Types exposing (..)
import Task
import Time


-- Based on: https://sascha.timme.xyz/elm-phoenix/
-- Code:  https://github.com/saschatimme/elm-phoenix


{-| Initialise the model
-}
new : Model msg channelsModel
new =
    { socketState = Disconnected, channelStates = ChannelStates.new, pushRef = 0, pushes = Dict.empty, previousChannelsModel = Nothing }


{-| Push an event to a channel
-}
push : String -> (Msg msg -> msg) -> Push msg -> Cmd msg
push endpoint parentMsg p =
    Cmd.map parentMsg <|
        Task.perform (\_ -> SendPush p) (Task.succeed Ok)


{-| Update the model
-}
update : Socket msg -> (channelsModel -> List (Channel msg)) -> channelsModel -> Msg msg -> Model msg channelsModel -> ( Model msg channelsModel, Cmd msg, Maybe msg )
update socket channelsFn channelsModel msg model =
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
                        , params = JE.dict identity JE.string (Dict.fromList socket.params)
                        }
                    , Nothing
                    )

                Connected ->
                    if Just channelsModel == model.previousChannelsModel then
                        ( model, Cmd.none, Nothing )
                    else
                        let
                            ( updatedChannelStates, newChannels, removedChannelObjs ) =
                                ChannelStates.update (channelsFn channelsModel) model.channelStates

                            newChannelsCmd =
                                if newChannels == [] then
                                    Cmd.none
                                else
                                    Ports.joinChannels <|
                                        List.map
                                            (\c ->
                                                { topic = c.topic
                                                , payload = Maybe.withDefault JE.null c.payload
                                                , onHandlers = { onOk = c.onJoin /= Nothing, onError = c.onJoinError /= Nothing, onTimeout = False }
                                                }
                                            )
                                            newChannels

                            cmds =
                                [ newChannelsCmd ]
                                    ++ List.map Ports.leaveChannel removedChannelObjs
                        in
                        ( { model | previousChannelsModel = Just channelsModel, channelStates = updatedChannelStates }, Cmd.batch cmds, Nothing )

        SendPush p ->
            case ChannelStates.getJoinedChannelObj p.topic model.channelStates of
                Nothing ->
                    -- let
                    --     _ =
                    --         Debug.log "Push on unjoined channel - ignoring: " p.topic
                    -- in
                    ( model, Cmd.none, Nothing )

                Just channelObj ->
                    -- TOOD: Do not store if no onHandlers
                    ( { model
                        | pushes = Dict.insert model.pushRef p model.pushes
                        , pushRef = model.pushRef + 1
                      }
                    , Ports.pushChannel
                        { ref = model.pushRef
                        , channel = channelObj
                        , event = p.event
                        , payload = p.payload
                        , onHandlers =
                            { onOk = p.onOk /= Nothing
                            , onError = p.onError /= Nothing
                            , onTimeout = True
                            }
                        }
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

        ChannelsCreated channelsCreated ->
            ( { model
                | channelStates =
                    List.foldl
                        (\( topic, channelObj ) acc ->
                            ChannelStates.setCreated topic channelObj acc
                        )
                        model.channelStates
                        channelsCreated
              }
            , Cmd.none
            , Nothing
            )

        ChannelJoinOk topic payload ->
            let
                updatedModel =
                    { model | channelStates = ChannelStates.setJoined topic model.channelStates }
            in
            case ChannelStates.getChannel topic model.channelStates of
                Just channel ->
                    case channel.onJoin of
                        Nothing ->
                            ( updatedModel, Cmd.none, Nothing )

                        Just onJoinMsg ->
                            ( updatedModel, Cmd.none, Just (onJoinMsg payload) )

                Nothing ->
                    -- let
                    --     _ =
                    --         Debug.log "ChannelJoinOk for channel no longer subscribed to: " topic
                    -- in
                    ( updatedModel, Cmd.none, Nothing )

        ChannelJoinError topic payload ->
            case ChannelStates.getChannel topic model.channelStates of
                Just channel ->
                    case channel.onJoinError of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onJoinError ->
                            ( model, Cmd.none, Just (onJoinError payload) )

                Nothing ->
                    ( model, Cmd.none, Nothing )

        ChannelLeaveOk topic payload ->
            case ChannelStates.getChannel topic model.channelStates of
                Just channel ->
                    case channel.onLeave of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onLeaveMsg ->
                            ( model, Cmd.none, Just (onLeaveMsg payload) )

                Nothing ->
                    ( model, Cmd.none, Nothing )

        ChannelLeaveError topic payload ->
            case ChannelStates.getChannel topic model.channelStates of
                Just channel ->
                    case channel.onLeaveError of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onLeaveError ->
                            ( model, Cmd.none, Just (onLeaveError payload) )

                Nothing ->
                    ( model, Cmd.none, Nothing )

        ChannelMessage topic event payload ->
            case ChannelStates.getChannel topic model.channelStates of
                Just channel ->
                    case Dict.get event channel.on of
                        Nothing ->
                            ( model, Cmd.none, Nothing )

                        Just onMsg ->
                            ( model, Cmd.none, Just (onMsg payload) )

                Nothing ->
                    ( model, Cmd.none, Nothing )


{-| Connect the socket
-}
connect : Socket msg -> (Msg msg -> msg) -> Sub msg
connect socket parentMsg =
    let
        tickInterval =
            if socket.debug then
                1000
            else
                100
    in
    Sub.map parentMsg <|
        Sub.batch
            [ Ports.channelEvent parseChannelEvent
            , Ports.channelsCreated ChannelsCreated
            , Ports.channelMessage (\( topic, event, payload ) -> ChannelMessage topic event payload)
            , Time.every tickInterval Tick
            ]


parseChannelEvent : Ports.ChannelEvent -> Msg msg
parseChannelEvent ( eventName, topic, data ) =
    let
        -- _ =
        --     Debug.log "parseChannelEvent" eventName
        --
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
            -- let
            --     _ =
            --         Debug.log "ChannelEvent parsing error : " ( eventName, topic, err )
            -- in
            NoOp


{-| Map the msg
-}
mapMsg : (a -> b) -> Msg a -> Msg b
mapMsg func msg =
    case msg of
        SendPush push_ ->
            SendPush (Phoenix.Push.map func push_)

        NoOp ->
            NoOp

        Tick time ->
            Tick time

        ChannelCreated a b ->
            ChannelCreated a b

        ChannelsCreated v ->
            ChannelsCreated v

        ChannelJoinOk a b ->
            ChannelJoinOk a b

        ChannelJoinError a b ->
            ChannelJoinError a b

        ChannelLeaveOk a b ->
            ChannelLeaveOk a b

        ChannelLeaveError a b ->
            ChannelLeaveError a b

        ChannelPushOk a b c ->
            ChannelPushOk a b c

        ChannelPushError a b c ->
            ChannelPushError a b c

        ChannelMessage a b c ->
            ChannelMessage a b c
