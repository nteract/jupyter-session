fs = require 'fs'
path = require 'path'
_ = require 'lodash'
child_process = require 'child_process'
uuid = require 'uuid'
jmp = require 'jmp'
EventEmitter = require('eventemitter2').EventEmitter2

JupyterTransport = require 'jupyter-transport-wrapper'

module.exports =
class Session extends EventEmitter
    constructor: (config, kernelProcess) ->
        super({wildcard: true})
        @language = config.language
        @executionCallbacks = {}

        config.address = "tcp://127.0.0.1"
        @transport = new JupyterTransport(config, kernelProcess)
        @transport.on 'shell.*', @_onMessage.bind(this, 'shell')
        @transport.on 'iopub.*', @_onMessage.bind(this, 'iopub')

    interrupt: ->
        @transport.interrupt

    # onResults is a callback that may be called multiple times
    # as results come in from the kernel
    execute: (code, onResults) ->
        requestId = "execute_" + uuid.v4()

        message = {}
        message.header =
            msg_id: requestId
            username: ""
            session: "00000000-0000-0000-0000-000000000000"
            msg_type: "execute_request"
            version: "5.0"

        message.content =
            code: code
            silent: false
            store_history: true
            user_expressions: {}
            allow_stdin: false

        @executionCallbacks[requestId] = onResults
        @transport.send 'shell', message

    complete: (code, onResults) ->
        requestId = "complete_" + uuid.v4()
        column = code.length

        message = {}
        message.header =
                msg_id: requestId
                username: ""
                session: "00000000-0000-0000-0000-000000000000"
                msg_type: "complete_request"
                version: "5.0"

        message.content =
                code: code
                text: code
                line: code
                cursor_pos: column

        @executionCallbacks[requestId] = onResults
        @transport.send 'shell', message

    # automatically rebroadcast the event
    # call any callbacks for completion or results
    _onMessage: (channel, message) ->
        # @transport.event is automatically populated
        # with the true name of the event
        @emit(@transport.event, message)
        if _.has(message, ['parent_header', 'msg_id'])
            callback = @executionCallbacks[message.parent_header.msg_id]
        if callback?
            callback(message)

    destroy: ->
        requestId = "shutdown_" + uuid.v4()

        message = {}
        message.header =
                msg_id: requestId
                username: ""
                session: "00000000-0000-0000-0000-000000000000"
                msg_type: "shutdown_request"
                version: "5.0"

        message.content =
                restart: false

        @transport.send 'control', message
        @transport.close()
