port module Phoenix.Ports exposing (..)

import Json.Encode as JE
import Phoenix.Channel exposing (Topic)
import Phoenix.ChannelStates exposing (ChannelObj)
import Phoenix.Types exposing (..)


type alias ChannelMsg =
    ( Topic, Event, JE.Value )


type alias ChannelEvent =
    ( String, Topic, JE.Value )


port channelMsg : (ChannelMsg -> msg) -> Sub msg


port channelEvent : (ChannelEvent -> msg) -> Sub msg


port channelsCreated : (List ( Topic, JE.Value ) -> msg) -> Sub msg


port connectSocket : { endpoint : String, params : JE.Value } -> Cmd msg



-- port joinChannel : { topic : Topic, payload : JE.Value } -> Cmd msg


port joinChannels : List { topic : Topic, payload : JE.Value } -> Cmd msg


port leaveChannel : ChannelObj -> Cmd msg


port pushChannel : { ref : Int, channel : ChannelObj, event : Event, payload : JE.Value } -> Cmd msg
