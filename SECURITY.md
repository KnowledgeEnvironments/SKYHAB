# Security policy

Please report vulnerabilities privately to [src@lispm.net](mailto:src@lispm.net). Include the affected
version, impact, reproduction steps using synthetic data, and any suggested mitigation. Do not
include production tokens, camera URLs, inventories, or device credentials.

The current 1.x design intentionally provides no TLS. Supported deployments provide confidentiality
and isolation through loopback, an isolated trusted IoT VLAN, or an authenticated, tightly scoped
tunnel to the host. Exposing SkyWire to an untrusted network is outside the supported threat model
and is not, by itself, a vulnerability. Authentication bypass, secret disclosure, unsafe command
construction, authorization errors, action-verification flaws, and malicious protocol inputs are
in scope.

Submitting a report creates no obligation or expectation of acknowledgement, response, review,
investigation, remediation, disclosure, support, payment, bounty, or any particular timeline. No
warranty, indemnity, or indemnification is offered or assumed. The software remains provided
**AS IS** under the [MIT License](LICENSE).
