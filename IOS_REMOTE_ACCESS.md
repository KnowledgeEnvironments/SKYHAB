# iOS remote access

skyHAB works over a site-to-site or on-demand VPN. Keep `AllowedIPs` as narrow as the deployment
allows: the skyhabd host plus only those camera endpoints that clients must reach directly.

For documentation, a fictional configuration might route `192.0.2.10/32` for skyhabd and
`192.0.2.41/32` for one camera. Replace these RFC 5737 addresses with your own private endpoints.

The app cannot play camera media through skyhabd: `CAMERA.STREAM` returns an authenticated RTSP
URL, then MobileVLCKit connects directly to the camera. Verify both SkyWire and RTSP reachability
over the real VPN path.

Never route the SkyWire port through a public interface. Prefer on-demand rules scoped to the
skyHAB bundle identifier and your private DNS suffix or SSID policy.
