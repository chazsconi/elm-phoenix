module Phoenix.Types exposing (..)

import Dict exposing (Dict)
import Json.Decode as JD
import Phoenix.Channel exposing (Topic)
import Phoenix.ChannelStates exposing (..)
import Phoenix.Push exposing (Push)
import Time


type alias Event =
    String


type alias PushRef =
    Int


type Msg msg
    = NoOp
    | Tick Time.Time -- Elm 0.19 Time.Posix
    | SendPush (Push msg)
    | ChannelCreated Topic JD.Value
    | ChannelJoinOk Topic JD.Value
    | ChannelJoinError Topic JD.Value
    | ChannelLeaveOk Topic JD.Value
    | ChannelLeaveError Topic JD.Value
    | ChannelPushOk Topic PushRef JD.Value
    | ChannelPushError Topic PushRef JD.Value
    | ChannelMessage Topic Event JD.Value


type SocketState
    = Disconnected
    | Connected


type alias Model msg =
    { socketState : SocketState
    , channelStates : ChannelStates
    , pushRef : PushRef
    , pushes : Dict PushRef (Push msg)
    }
