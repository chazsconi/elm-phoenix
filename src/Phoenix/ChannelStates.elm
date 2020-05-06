module Phoenix.ChannelStates exposing (ChannelObj, ChannelStates, new, setCreated, update)

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


setCreated : Topic -> ChannelObj -> ChannelStates -> ChannelStates
setCreated topic1 channelObj (ChannelStates channelStates) =
    ChannelStates <| Dict.insert topic1 (PendingJoin channelObj) channelStates


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
newTopics : List Topic -> ChannelStates -> List Topic
newTopics topics1 channelStates =
    List.foldl
        (\topic acc ->
            if member topic channelStates then
                acc
            else
                topic :: acc
        )
        []
        topics1


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


update : List (Channel msg) -> ChannelStates -> ( ChannelStates, List Topic, List ChannelObj )
update channels channelStates =
    let
        topics1 =
            List.map .topic channels

        newTopics1 =
            newTopics topics1 channelStates

        ( removedTopics1, removedChannelObjs ) =
            removedTopics topics1 channelStates

        updatedChannelStates =
            channelStates
                |> addTopics newTopics1
                |> removeTopics removedTopics1
    in
    ( updatedChannelStates, newTopics1, removedChannelObjs )
