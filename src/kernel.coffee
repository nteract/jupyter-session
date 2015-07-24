fs = require 'fs'
path = require 'path'
_ = require 'lodash'
child_process = require 'child_process'
uuid = require 'uuid'
jmp = require 'jmp'

# JupyterTransport = require 'jupyter-transport-wrapper'

ConfigManager = require './config-manager'

module.exports =
class Kernel
    constructor: (config, @kernelProcess) ->
        console.log "Kernel configuration:", config

        @language = config.language
        @signatureKey = config.key
        @signatureScheme = config.signature_scheme

        @executionCallbacks = {}

        @shellSocket = new jmp.Socket 'dealer', @signatureScheme, @signatureKey
        @controlSocket = new jmp.Socket 'dealer', @signatureScheme, @signatureKey
        @ioSocket = new jmp.Socket 'sub', @signatureScheme, @signatureKey

        @shellSocket.identity = 'dealer' + @language + + uuid.v4()
        @controlSocket.identity = 'control' + @language + + uuid.v4()
        @ioSocket.identity = 'sub' + @language + + uuid.v4()

        @shellSocket.connect('tcp://127.0.0.1:' + config.shell_port)
        @controlSocket.connect('tcp://127.0.0.1:' + config.control_port)
        @ioSocket.connect('tcp://127.0.0.1:' + config.iopub_port)
        @ioSocket.subscribe('')

        @shellSocket.on 'message', @onShellMessage.bind(this)
        @ioSocket.on 'message', @onIOMessage.bind(this)

    interrupt: ->
        @kernelProcess.kill('SIGINT')

    # onResults is a callback that may be called multiple times
    # as results come in from the kernel
    _execute: (code, requestId, onResults) ->
        header =
                msg_id: requestId
                username: ""
                session: 0
                msg_type: "execute_request"
                version: "5.0"

        content =
                code: code
                silent: false
                store_history: true
                user_expressions: {}
                allow_stdin: false

        message = new jmp.Message()
        message.header = header
        message.content = content

        # signedMessage = message.sign(@signatureScheme, @signatureKey)

        @executionCallbacks[requestId] = onResults
        @shellSocket.send message

    execute: (code, onResults) ->
        requestId = "execute_" + uuid.v4()
        @_execute(code, requestId, onResults)

    executeWatch: (code, onResults) ->
        requestId = "watch_" + uuid.v4()
        @_execute(code, requestId, onResults)

    complete: (code, onResults) ->
        requestId = "complete_" + uuid.v4()
        column = code.length

        header =
                msg_id: requestId
                username: ""
                session: 0
                msg_type: "complete_request"
                version: "5.0"

        content =
                code: code
                text: code
                line: code
                cursor_pos: column

        message = new jmp.Message()
        message.header = header
        message.content = content

        # signedMessage = message.sign(@signatureScheme, @signatureKey)

        @executionCallbacks[requestId] = onResults
        @shellSocket.send message

    addWatchCallback: (watchCallback) ->
        @watchCallbacks.push(watchCallback)

    onShellMessage: (message) ->=
        if _.has(message, ['parent_header', 'msg_id'])
            callback = @executionCallbacks[message.parent_header.msg_id]
        if callback?
            callback(message)

    onIOMessage: (message) ->
        if message.header.msg_type == 'status'
            status = message.content.execution_state

            # if status == 'idle' and _.has(message, ['parent_header', 'msg_id'])
            #     if message.parent_header.msg_id.startsWith('execute')
            #         _.forEach @watchCallbacks, (watchCallback) ->
            #             watchCallback()

        if _.has(message, ['parent_header', 'msg_id'])
            callback = @executionCallbacks[message.parent_header.msg_id]
        if callback?
            callback(message)

    # getResultObject: (message) ->
    #     if message.header.msg_type == 'pyout' or
    #        message.header.msg_type == 'display_data' or
    #        message.header.msg_type == 'execute_result'
    #         if message.content.data['text/html']?
    #             return {
    #                 data: message.content.data['text/html']
    #                 type: 'text/html'
    #                 stream: 'pyout'
    #             }
    #         if message.content.data['image/svg+xml']?
    #             return {
    #                 data: message.content.data['image/svg+xml']
    #                 type: 'image/svg+xml'
    #                 stream: 'pyout'
    #             }
    #
    #         imageKeys = _.filter _.keys(message.content.data), (key) ->
    #             return key.startsWith('image')
    #         imageKey = imageKeys[0]
    #
    #         if imageKey?
    #             return {
    #                 data: message.content.data[imageKey]
    #                 type: imageKey
    #                 stream: 'pyout'
    #             }
    #         else
    #             return {
    #                 data: message.content.data['text/plain']
    #                 type: 'text'
    #                 stream: 'pyout'
    #             }
    #     else if message.header.msg_type == 'stdout' or
    #             message.idents[0].toString() == 'stdout' or
    #             message.idents[0].toString() == 'stream.stdout' or
    #             message.content.name == 'stdout'
    #         return {
    #             data: message.content.text ? message.content.data
    #             type: 'text'
    #             stream: 'stdout'
    #         }
    #     else if message.type == 'pyerr' or message.type == 'error'
    #         stack = message.content.traceback
    #         stack = _.map stack, (item) -> item.trim()
    #         stack = stack.join('\n')
    #         return {
    #             data: stack
    #             type: 'text'
    #             stream: 'error'
    #         }

    destroy: ->
        requestId = uuid.v4()

        header =
                msg_id: requestId
                username: ""
                session: 0
                msg_type: "shutdown_request"
                version: "5.0"

        content =
                restart: false

        message = new jmp.Message()
        message.header = header
        message.content = content

        # signedMessage = message.sign(@signatureScheme, @signatureKey)

        @controlSocket.send message
        @shellSocket.close()
        @ioSocket.close()
        @controlSocket.close()

        @kernelProcess.kill('SIGKILL')
