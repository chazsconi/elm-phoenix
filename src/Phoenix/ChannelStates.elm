module Phoenix.ChannelStates exposing (ChannelObj, ChannelStates, getJoinedChannelObj, new, setCreated, setJoined, update)

import Dict exposing (Dict)
import Json.Encode as JE
import Phoenix.Channel exposing (Channel, Topic)


type ChannelStates
    = ChannelStates (Dict Topic ChannelState)


{-| JS channel object
-}
type alias ChannelObj =
    JE.Value


type ChannelState
    = Creating
    | PendingJoin ChannelObj
    | Joined ChannelObj


new : ChannelStates
new =
    ChannelStates Dict.empty


getJoinedChannelObj : Topic -> ChannelStates -> Maybe ChannelObj
getJoinedChannelObj topic (ChannelStates channelStates) =
    Dict.get topic channelStates
        |> Maybe.andThen
            (\channelState ->
                case channelState of
                    Creating ->
                        Nothing

                    PendingJoin channelObj ->
                        Just channelObj

                    Joined channelObj ->
                        Just channelObj
            )


setCreated : Topic -> ChannelObj -> ChannelStates -> ChannelStates
setCreated topic1 channelObj (ChannelStates channelStates) =
    ChannelStates <| Dict.insert topic1 (PendingJoin channelObj) channelStates


setJoined : Topic -> ChannelStates -> ChannelStates
setJoined topic_ (ChannelStates channelStates) =
    ChannelStates <|
        Dict.update topic_
            (\channelState ->
                case channelState of
                    Nothing ->
                        Nothing

                    Just (PendingJoin obj) ->
                        Just (Joined obj)

                    Just (Joined obj) ->
                        -- let
                        --     _ =
                        --         Debug.log "setJoined for already joined channel: " topic_
                        -- in
                        Just (Joined obj)

                    Just Creating ->
                        -- let
                        --     _ =
                        --         Debug.log "setJoined for creating channel: " topic_
                        -- in
                        Just Creating
            )
            channelStates


insert : Topic -> ChannelStates -> ChannelStates
insert topic1 (ChannelStates channelStates) =
    ChannelStates <| Dict.insert topic1 Creating channelStates


remove : Topic -> ChannelStates -> ChannelStates
remove topic1 (ChannelStates cs) =
    ChannelStates <| Dict.remove topic1 cs


member : Topic -> ChannelStates -> Bool
member topic (ChannelStates cs) =
    Dict.member topic cs


foldl : (Topic -> ChannelState -> b -> b) -> b -> ChannelStates -> b
foldl func acc (ChannelStates cs) =
    Dict.foldl func acc cs


topics : ChannelStates -> List Topic
topics (ChannelStates cs) =
    Dict.keys cs


{-| Topics that are in the list of topics but not in channel state
-}
newChannels : List (Channel msg) -> ChannelStates -> List (Channel msg)
newChannels channels channelStates =
    List.foldl
        (\channel acc ->
            if member channel.topic channelStates then
                acc
            else
                channel :: acc
        )
        []
        channels


removedTopics : List Topic -> ChannelStates -> ( List Topic, List ChannelObj )
removedTopics topics1 channelStates =
    foldl
        (\topic channelState ( topicAcc, objAcc ) ->
            if List.member topic topics1 then
                ( topicAcc, objAcc )
            else
                case channelState of
                    -- Shouldn't happen
                    Creating ->
                        ( topicAcc, objAcc )

                    PendingJoin obj ->
                        ( topic :: topicAcc, obj :: objAcc )

                    Joined obj ->
                        ( topic :: topicAcc, obj :: objAcc )
        )
        ( [], [] )
        channelStates


addTopics : List Topic -> ChannelStates -> ChannelStates
addTopics topics1 channelStates =
    List.foldl insert channelStates topics1


removeTopics : List Topic -> ChannelStates -> ChannelStates
removeTopics topics1 channelStates =
    List.foldl remove channelStates topics1


update : List (Channel msg) -> ChannelStates -> ( ChannelStates, List (Channel msg), List ChannelObj )
update channels channelStates =
    let
        newChannels1 =
            newChannels channels channelStates

        ( removedTopics1, removedChannelObjs ) =
            removedTopics (List.map .topic channels) channelStates

        updatedChannelStates =
            channelStates
                |> addTopics (List.map .topic newChannels1)
                |> removeTopics removedTopics1
    in
    ( updatedChannelStates, newChannels1, removedChannelObjs )
