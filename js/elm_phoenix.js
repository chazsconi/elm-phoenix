import {
  Socket
} from "phoenix"

export function init(app) {
  let socket = null;

  let log = (msg, data) => {
    console.log(msg, data)
  }

  let pushHandlers = (push, channel, type, ref) => {
    push
      .receive("ok", (msg) => {
        if (channel.topic.startsWith("xbsxx:")) {
          console.log("Skipping ", channel.topic)
        } else {
          log("push ok", {
            topic: channel.topic,
            type: type,
            ref: ref
          })
          app.ports.channelEvent.send(["pushOk", channel.topic, {
            type: type,
            ref: ref,
            payload: msg
          }])
        }
      })
      .receive("error", (reasons) => {
        log("push failed", reasons)
        app.ports.channelEvent.send(["pushError", channel.topic, {
          type: type,
          ref: ref,
          payload: reasons
        }])
      })
      .receive("timeout", () => {
        log("push timeout")
      })
  }

  app.ports.connectSocket.subscribe(data => {
    log("connect socket: ", {
      endpoint: data.endpoint,
      params: data.params
    })

    socket = new Socket(data.endpoint, {
      params: data.params
    })

    socket.connect()
    log("Socket connected: ", socket)
  })

  app.ports.joinChannels.subscribe(channelSpecs => {

    let channels =
      channelSpecs.map(data => {
        log("joinChannel: ", {
          topic: data.topic,
          payload: data.payload
        })

        let channel = socket.channel(data.topic, data.payload)

        channel.onMessage = (e, payload, ref) => {
          app.ports.channelEvent.send(["message", channel.topic, {
            event: e,
            payload: payload
          }])
          return payload
        }

        // let push = channel.join()
        // pushHandlers(push, channel, "join")

        return channel
      })
    app.ports.channelsCreated.send(channels.map(channel => [channel.topic, channel]));

    channels.map( channel => {
      let push = channel.join()
      pushHandlers(push, channel, "join")
    })

  });

  // // Join Channel
  // app.ports.joinChannel.subscribe(data => {
  //
  //   log("joinChannel: ", {
  //     topic: data.topic,
  //     payload: data.payload
  //   })
  //
  //   let channel = socket.channel(data.topic, data.payload)
  //
  //   channel.onMessage = (e, payload, ref) => {
  //     app.ports.channelEvent.send(["message", channel.topic, {
  //       event: e,
  //       payload: payload
  //     }])
  //     return payload
  //   }
  //
  //   app.ports.channelEvent.send(["created", channel.topic, {
  //     channel: channel
  //   }])
  //
  //   if (data.topic.startsWith("xbs:")) {
  //     console.log("Skipping join ", data.topic)
  //   } else {
  //
  //
  //     let push = channel.join()
  //     pushHandlers(push, channel, "join")
  //   }
  // });

  // Leave channel
  app.ports.leaveChannel.subscribe(channel => {
    log("leaveChannel: ", {
      channel: channel
    })

    let push = channel.leave()
    pushHandlers(push, channel, "leave")
  })

  // Push
  app.ports.pushChannel.subscribe(data => {
    log("Push", {
      topic: data.channel.topic,
      event: data.event,
      payload: data.payload,
      ref: data.ref
    })

    let channel = data.channel
    let push = channel.push(data.event, data.payload, 10000)
    pushHandlers(push, channel, "msg", data.ref)
  })
}
