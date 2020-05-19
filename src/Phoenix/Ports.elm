port module Phoenix.Ports exposing (..)

import Json.Encode as JE
import Phoenix.Channel exposing (Topic)
import Phoenix.ChannelStates exposing (ChannelObj)
import Phoenix.Types exposing (..)


type alias ChannelMsg =
    ( Topic, Event, JE.Value )


type alias OnHandlers =
    { onOk : Bool, onError : Bool, onTimeout : Bool }


type alias PushReply =
    { eventName : String, topic : Topic, pushType : String, ref : Maybe Int, payload : JE.Value }


port channelMessage : (( Topic, String, JE.Value ) -> msg) -> Sub msg


port pushReply : (PushReply -> msg) -> Sub msg


port channelsCreated : (List ( Topic, ChannelObj ) -> msg) -> Sub msg


port connectSocket : { endpoint : String, params : JE.Value } -> Cmd msg


port joinChannels : List { topic : Topic, payload : JE.Value, onHandlers : OnHandlers } -> Cmd msg


port leaveChannel : ChannelObj -> Cmd msg


port pushChannel : { ref : Int, channel : ChannelObj, event : Event, payload : JE.Value, onHandlers : OnHandlers } -> Cmd msg
