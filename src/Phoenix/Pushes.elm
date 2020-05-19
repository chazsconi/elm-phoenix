module Phoenix.Pushes exposing (PushRef, Pushes, insert, new, pop)

import Dict exposing (Dict)
import Phoenix.Push exposing (Push)


type alias PushRef =
    Int


type alias Pushes msg =
    { nextRef : Int, dict : Dict PushRef (Push msg) }


new : Pushes msg
new =
    { nextRef = 1, dict = Dict.empty }


insert : Push msg -> Pushes msg -> ( PushRef, Pushes msg )
insert push pushes =
    ( pushes.nextRef, { pushes | nextRef = pushes.nextRef + 1, dict = Dict.insert pushes.nextRef push pushes.dict } )


pop : PushRef -> Pushes msg -> Maybe ( Push msg, Pushes msg )
pop ref pushes =
    case Dict.get ref pushes.dict of
        Nothing ->
            Nothing

        Just push ->
            Just ( push, { pushes | dict = Dict.remove ref pushes.dict } )
