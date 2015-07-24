# jupyter-session

This API is not finalized.

## Usage

```javascript
var Session = require('jupyter-session');

pythonSession = new Session(
    {
        version: 5,
        signature_scheme: 'sha256',
        key: '<the signing key>',
        transport: 'tcp',
        ip: '127.0.0.1',
        hb_port: 60868,
        control_port: 60869,
        shell_port: 60870,
        stdin_port: 60871,
        iopub_port: 60872
    },
    <'handle to kernel process, if available'>
);

// use wildcards to get all messages on a channel
pythonSession.on('shell.*', function(message) {
    // message will be a jmp.Message
});

pythonSession.execute(code, function(results) {
    // results will be a jmp.Message

    // this function may be called several times
    // as additional messages come in from the kernel
});

pythonSession.complete(code, function(results) {
    // results will be a jmp.Message
});
```
