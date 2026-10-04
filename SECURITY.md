# Security

This package is an offline QR encoder. It does not fetch payload URLs or inspect
what a QR link will do. Treat scanned destinations as untrusted. Resource bounds
limit single requests; applications must also bound request rates and concurrency.

Please report reproducible vulnerabilities privately to the repository owner
using GitHub's supported private reporting route if it is enabled. Do not post
secrets in public issues. There is no promised response SLA or GS1 certification.
