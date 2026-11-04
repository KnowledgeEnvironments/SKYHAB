# SkyWire/1 protocol

This document is normative. The key words MUST, MUST NOT, SHOULD, and MAY carry
their usual standards meaning.

## Transport

SkyWire is an ordered, reliable, eight-bit byte stream. The current V1 implementation
supports TCP; Unix-domain transport is future work. TCP defaults to port 3636. TLS is neither required nor negotiated
by SkyWire/1.

The server sends a `HELLO` event immediately after connection. A TCP client MUST
authenticate before any command except `PING`, `VERSION`, or `AUTH`.

## Netstring framing

Every message is one outer netstring. Its payload is a concatenation of inner
netstrings called tokens.

```abnf
digit       = %x30-39
length      = 1*digit
netstring   = length ":" *OCTET ","  ; exactly length payload octets
message     = netstring               ; payload is 1*token
token       = netstring
```

Lengths are unsigned decimal with no sign and no leading zero except `0`. A
parser MUST reject overflow, a missing comma, non-decimal length, an outer frame
larger than 1 MiB, more than 256 tokens, or an incomplete frame after timeout.
Implementations MUST accept arbitrary stream fragmentation and multiple frames
in one read.

`CAMERA.STREAM` returns a complete credential-bearing RTSP URL to an authenticated client.
The client hands it directly to its embedded RTSP decoder; SkyWire does not proxy media bytes.
Clients MUST treat the response as a secret and MUST NOT log it unless the operator has
explicitly accepted that exposure.

`STORAGE.FILES` is an authenticated, bounded snapshot rather than a subscription. The server
normalizes portable numeric and display fields and may report the backing store unavailable
without treating that condition as a protocol failure. Directory entries are not resources.

## Message tokens

The first token identifies the family:

- `Q`: request
- `R`: response
- `E`: asynchronous event
- `H`: server hello

Requests are:

```text
Q, request-id, COMMAND, argument-name, typed-value, ...
```

Responses are:

```text
R, request-id, OK|MORE|END, record-type, field-name, typed-value, ...
R, request-id, ERR, error-code, retryable, message, field-name, typed-value, ...
```

Events are:

```text
E, subscription-id, sequence, topic, field-name, typed-value, ...
```

Hello is:

```text
H, major, minor, server-id, max-frame, feature, ...
```

IDs and names are ASCII. Request IDs are nonzero unsigned decimal numbers chosen
by the client and unique among its outstanding requests. Responses may arrive in
a different order. `MORE` carries one flat record; `END` completes a streaming
response. Events may interleave with responses.

## Typed values

A typed-value token begins with one type byte followed by its representation:

| Prefix | Meaning | Representation |
|---|---|---|
| `s` | string | UTF-8 bytes |
| `i` | signed integer | canonical decimal ASCII |
| `u` | unsigned integer | canonical decimal ASCII |
| `f` | finite decimal | locale-independent decimal ASCII |
| `b` | boolean | `b0` or `b1` |
| `t` | timestamp | RFC 3339 UTC with fractional seconds allowed |
| `x` | opaque bytes | remaining bytes unchanged |
| `n` | null | exactly `n` |

Unknown field names MUST be ignored. Unknown type prefixes make that record
unusable but MUST NOT desynchronize the connection. Repeated records represent
lists; nested wire values are deliberately absent.

## Versioning

The current version is 1.0. A major-version difference is incompatible. Minor
versions are additive: commands, records, fields, enum values, and features may
be added. Existing meanings and types MUST NOT change within a major version.
Clients declare their major, minor, and optional features with `VERSION`.

## Authentication and roles

`AUTH` accepts `client` and `token` arguments. Tokens contain at least 256 bits of
randomness. The daemon stores only token hashes and compares them in constant
time. Successful authentication returns actor ID and role. Three roles exist:

- `viewer`: discovery, state, metrics, and events
- `operator`: viewer plus permitted device actions
- `admin`: operator plus inventory and token administration

Authentication failure does not reveal whether the client name or token was
wrong. Servers SHOULD rate-limit repeated failures.

## Subscriptions

`EVENT.WATCH` returns a subscription ID and then emits `E` messages. Every event
has a monotonically increasing persisted sequence. A client may supply `since`.
If retained history cannot fill the gap, the server emits `event.gap` with the
oldest available and current sequences. Heartbeats carry no state and keep idle
connections observable.

## Compatibility profile for old clients

An old client may issue one request at a time, ignore events, use only ASCII
strings, poll instead of subscribe, and ignore unknown records. It needs only a
decimal counter, byte copying, and a small token-state parser. It does not need
JSON, TLS, floating-point binary decoding, threads, or native 32-bit byte order.
