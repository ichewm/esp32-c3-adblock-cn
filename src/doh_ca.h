#pragma once
// Root CA for the DoH upstream (AliDNS, https://223.5.5.5/dns-query).
// GlobalSign ECC Root CA - R5 — the root behind *.alidns.com / IP:223.5.5.5.
// sha256 fp 17:9f:bc:14:8a:3d:d0:0f:d2:4e:a1:34:58:cc:43:bf:a7:f5:9c:81:82:d7:83:a5:13:f6:eb:ec:10:0c:89:24
// (matches Globalsign published value). Fetched from the curl/Mozilla CA bundle.
// If AliDNS ever re-roots, DoH handshake fails and the firmware falls back to
// plain UDP forwarding automatically — update this cert then.
static const char DOH_ROOT_CA[] PROGMEM = R"CERT(
-----BEGIN CERTIFICATE-----
MIICHjCCAaSgAwIBAgIRYFlJ4CYuu1X5CneKcflK2GwwCgYIKoZIzj0EAwMwUDEkMCIGA1UECxMb
R2xvYmFsU2lnbiBFQ0MgUm9vdCBDQSAtIFI1MRMwEQYDVQQKEwpHbG9iYWxTaWduMRMwEQYDVQQD
EwpHbG9iYWxTaWduMB4XDTEyMTExMzAwMDAwMFoXDTM4MDExOTAzMTQwN1owUDEkMCIGA1UECxMb
R2xvYmFsU2lnbiBFQ0MgUm9vdCBDQSAtIFI1MRMwEQYDVQQKEwpHbG9iYWxTaWduMRMwEQYDVQQD
EwpHbG9iYWxTaWduMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAER0UOlvt9Xb/pOdEh+J8LttV7HpI6
SFkc8GIxLcB6KP4ap1yztsyX50XUWPrRd21DosCHZTQKH3rd6zwzocWdTaRvQZU4f8kehOvRnkmS
h5SHDDqFSmafnVmTTZdhBoZKo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAd
BgNVHQ4EFgQUPeYpSJvqB8ohREom3m7e0oPQn1kwCgYIKoZIzj0EAwMDaAAwZQIxAOVpEslu28Yx
uglB4Zf4+/2a4n0Sye18ZNPLBSWLVtmg515dTguDnFt2KaAJJiFqYgIwcdK1j1zqO+F4CYWodZI7
yFz9SO8NdCKoCOJuxUnOxwy8p2Fp8fc74SrL+SvzZpA3
-----END CERTIFICATE-----
)CERT";
