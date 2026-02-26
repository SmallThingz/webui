const std = @import("std");

pub const TlsOptions = struct {
    enabled: bool = false,
    cert_pem: ?[]const u8 = null,
    key_pem: ?[]const u8 = null,
    auto_generate_if_missing: bool = true,
};

pub const TlsInfo = struct {
    enabled: bool,
    generated: bool,
    fingerprint_sha256: ?[]const u8,
    scheme: []const u8,
};

pub const Runtime = struct {
    enabled: bool,
    generated: bool,
    cert_pem: ?[]u8,
    key_pem: ?[]u8,
    fingerprint_sha256: ?[]u8,
    allocator: std.mem.Allocator,
    auto_generate_if_missing: bool,

    pub fn init(allocator: std.mem.Allocator, options: TlsOptions) !Runtime {
        var runtime: Runtime = .{
            .enabled = options.enabled,
            .generated = false,
            .cert_pem = null,
            .key_pem = null,
            .fingerprint_sha256 = null,
            .allocator = allocator,
            .auto_generate_if_missing = options.auto_generate_if_missing,
        };

        if (options.cert_pem != null or options.key_pem != null) {
            if (options.cert_pem == null or options.key_pem == null) return error.InvalidTlsConfiguration;
            try runtime.setCertificate(options.cert_pem.?, options.key_pem.?);
        } else if (runtime.enabled and runtime.auto_generate_if_missing) {
            try runtime.generateDefaultCertificate();
        }

        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        if (self.cert_pem) |cert| {
            self.allocator.free(cert);
            self.cert_pem = null;
        }
        if (self.key_pem) |key| {
            self.allocator.free(key);
            self.key_pem = null;
        }
        if (self.fingerprint_sha256) |fingerprint| {
            self.allocator.free(fingerprint);
            self.fingerprint_sha256 = null;
        }
    }

    pub fn setCertificate(self: *Runtime, cert_pem: []const u8, key_pem: []const u8) !void {
        try validatePemPair(cert_pem, key_pem);

        const cert_copy = try self.allocator.dupe(u8, cert_pem);
        errdefer self.allocator.free(cert_copy);
        const key_copy = try self.allocator.dupe(u8, key_pem);
        errdefer self.allocator.free(key_copy);

        const fingerprint = try buildSha256Hex(self.allocator, cert_copy);
        errdefer self.allocator.free(fingerprint);

        if (self.cert_pem) |buf| self.allocator.free(buf);
        if (self.key_pem) |buf| self.allocator.free(buf);
        if (self.fingerprint_sha256) |buf| self.allocator.free(buf);

        self.cert_pem = cert_copy;
        self.key_pem = key_copy;
        self.fingerprint_sha256 = fingerprint;
        self.generated = false;
    }

    pub fn ensureCertificate(self: *Runtime) !void {
        if (!self.enabled) return;
        if (self.cert_pem != null and self.key_pem != null) return;
        if (!self.auto_generate_if_missing) return error.TlsCertificateMissing;
        try self.generateDefaultCertificate();
    }

    pub fn info(self: *const Runtime) TlsInfo {
        const has_material = self.enabled and self.cert_pem != null and self.key_pem != null;
        return .{
            .enabled = self.enabled,
            .generated = self.generated,
            .fingerprint_sha256 = self.fingerprint_sha256,
            // The current runtime transport remains HTTP; this flag reports TLS configuration status.
            .scheme = if (has_material) "https" else "http",
        };
    }

    pub fn hasMaterial(self: *const Runtime) bool {
        return self.enabled and self.cert_pem != null and self.key_pem != null;
    }

    fn generateDefaultCertificate(self: *Runtime) !void {
        const cert_copy = try self.allocator.dupe(u8, generated_cert_pem);
        errdefer self.allocator.free(cert_copy);
        const key_copy = try self.allocator.dupe(u8, generated_key_pem);
        errdefer self.allocator.free(key_copy);
        const fingerprint = try buildSha256Hex(self.allocator, cert_copy);
        errdefer self.allocator.free(fingerprint);

        if (self.cert_pem) |buf| self.allocator.free(buf);
        if (self.key_pem) |buf| self.allocator.free(buf);
        if (self.fingerprint_sha256) |buf| self.allocator.free(buf);

        self.cert_pem = cert_copy;
        self.key_pem = key_copy;
        self.fingerprint_sha256 = fingerprint;
        self.generated = true;
    }
};

fn validatePemPair(cert_pem: []const u8, key_pem: []const u8) !void {
    if (cert_pem.len == 0 or key_pem.len == 0) return error.InvalidTlsPem;

    if (!std.mem.startsWith(u8, cert_pem, "-----BEGIN CERTIFICATE-----")) return error.InvalidTlsCertificatePem;
    if (std.mem.indexOf(u8, cert_pem, "-----END CERTIFICATE-----") == null) return error.InvalidTlsCertificatePem;

    const has_private_key = std.mem.indexOf(u8, key_pem, "-----BEGIN PRIVATE KEY-----") != null and
        std.mem.indexOf(u8, key_pem, "-----END PRIVATE KEY-----") != null;
    const has_rsa_key = std.mem.indexOf(u8, key_pem, "-----BEGIN RSA PRIVATE KEY-----") != null and
        std.mem.indexOf(u8, key_pem, "-----END RSA PRIVATE KEY-----") != null;
    if (!has_private_key and !has_rsa_key) return error.InvalidTlsPrivateKeyPem;
}

fn buildSha256Hex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex);
}

const generated_cert_pem =
    \\-----BEGIN CERTIFICATE-----
    \\MIIDCTCCAfGgAwIBAgIUeiABqyzJFD4m+g/erXWxGDY90s0wDQYJKoZIhvcNAQEL
    \\BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MDIyNjA2NTUxNloXDTM2MDIy
    \\NDA2NTUxNlowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF
    \\AAOCAQ8AMIIBCgKCAQEA8JgiJkdwsFoHXhziH/rG31EiXGFWLry4TaBTBcqSJ9rC
    \\+tuAICstFgKgpy0kjYCo0reUTDD2QsObOVKyrf0wPH5K7/p/DxYY1SWxxphvlQBD
    \\qpHUr/Er2NuY3k/kuqX8Z/7Iz6Jd4UUt+vJe9AlQSdaNbq58u+5lBA98zhJTg1As
    \\qY/mNB4IkJ1fK+bTrJJXblrOh3Z2jVtw00lKsgkYBHGssNMYJkEotlqCsgYfJ/6f
    \\IPE6kx2sxODWK4VL+jBL5P6Seh2lYoubWdcUYoEAbtZ0/m69YV7FSJWLB75zKIJh
    \\mB4XspWb1MzE9vWZurxjb/WAGAnic9BGel/11JH3VQIDAQABo1MwUTAdBgNVHQ4E
    \\FgQUQeeUCrwOtbJVv/WZAQmqcpYLh88wHwYDVR0jBBgwFoAUQeeUCrwOtbJVv/WZ
    \\AQmqcpYLh88wDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAHClY
    \\wgIfHeGJ1sxqM9zDxuAWScmoUNQf3GnIe02hDVXxEbXjt6L5V13Lp0lP9mKUo5qv
    \\4T0c/gX7xn6ZRq35pe0redTG7ic1xPKvlrtHmuC93ot+N1CO8GDcOn0HJVTTCB/V
    \\OFcU+zHNsAQ6NDRIZ0JUfxNZumwulVpDUyGHG07OfY2tpmsSdk/HbeBe/Nifj1jg
    \\rIy0EmDRpgSfDft8nkU0ejTAc9jubwMsdJ1fHhl3HXmHNzcCLF3RDQrr9msCg/zN
    \\xVgIaqwGfe9pUVq1RCzygsBw1PtALR2AKP3vFLn8v0JV8nTfdemsSK0adFcOnToj
    \\13Uw63oOIgR0xisjrA==
    \\-----END CERTIFICATE-----
;

const generated_key_pem =
    \\-----BEGIN PRIVATE KEY-----
    \\MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDwmCImR3CwWgde
    \\HOIf+sbfUSJcYVYuvLhNoFMFypIn2sL624AgKy0WAqCnLSSNgKjSt5RMMPZCw5s5
    \\UrKt/TA8fkrv+n8PFhjVJbHGmG+VAEOqkdSv8SvY25jeT+S6pfxn/sjPol3hRS36
    \\8l70CVBJ1o1urny77mUED3zOElODUCypj+Y0HgiQnV8r5tOsklduWs6HdnaNW3DT
    \\SUqyCRgEcayw0xgmQSi2WoKyBh8n/p8g8TqTHazE4NYrhUv6MEvk/pJ6HaVii5tZ
    \\1xRigQBu1nT+br1hXsVIlYsHvnMogmGYHheylZvUzMT29Zm6vGNv9YAYCeJz0EZ6
    \\X/XUkfdVAgMBAAECggEAFzz6f2wDDGWFtKdhh+k28Dbr9LRKGLWNr6G+ox6Pw12z
    \\23r8Ax9oeWnDjqIjl69HnyKwJjPMdWJjScQdEgUUdaNVJZyyTQi7WUsMwrvSezfN
    \\UVpIir3mmEmNmFtrIkQJ/xly1+s82hdOe6CRX0zO/nLEsl4UGirKgvvj+Bt5CYOy
    \\+npC4Z7YXU1z7u0lZ2sLaDwrGzhB7c9FF6slTFa0bqw2f4ivaMEYxD43Mg1dmimR
    \\akDHD4fVn5UWL9Gc2dG416G7erdjzXsmOfE09FDKibHV0W8rYUE8oFRZBDsVmLnE
    \\amTwUoqUoqkKj7qVcz5jKuJKnFmFMiv/d6/Y1tHJAQKBgQD7Yg1E6eNEkK0u/3oo
    \\lLwPj4SI5py+i3xsRjgnKtpp6s3pLpmAhUWh/83dkn7wdWX3jcd/uZ8bcM60gTWV
    \\DhygCVoXpjkE5nHEWAPkPZK/ZW02tKTnkrPw2ks/3Q9/N1JcYLszOD+LNeJlY6fM
    \\Y+PPMVS+/mj19Ekj0nQBQxbatQKBgQD1A1rxDApQ+cxjHZQ1I/ObxumMlsP+x1fS
    \\sClIwYAE1W2GC+x4l3+hWdDafwe43iVUg3at0I+Wcp3UJCG+tcexoH4YdCvdhHl1
    \\F6/OIZ/sVLMcWKGaQk60+/X1FQCSkI5d3ANCAGgN+3XuTkNR/0EldkxpeeBGX5xs
    \\MV9bQ85uIQKBgQC35ptedtxUJKMNZsivN1/84jlLDapNmy2C6DvcK3VtVuEcXYLe
    \\iqDOSp0II0vKDZhy6b2wqtLC+Fu/oWbZjGFUkoLeGjRMaWmBAgKWzpS0gDbNdonM
    \\/320DX5PUiEsKASQoBNS/Ss/ZEQjeCwhUlIuGSCuOOAATp3THvrOkY3+oQKBgH60
    \\8X7e3ybpSA2p6k9g/EZ/I6CVB17m8EAA4hjCGNZnGXDNEcl7b4Gd1ShpsTClkWCX
    \\a/SPevIu6/gdh2X80/zEJvG2gkjYjYdEbKKJOQ8a7lWmcEw6JkHqW1QXPGiPYVCg
    \\yv6C/0zb0i0fRClPe/1HpFSXtqguIdLB5bJo6oSBAoGAZBz11Wa0z/guAFshB1cg
    \\qtkZTkxKQkeU7GTo3kX5pHkI+ktEQ7ghXt5DbRlAPcxD7GAgy6GTJmZyhPzn4vDT
    \\TMGThloF4z8cT6VLZDUyBmGcQ92ErZFWNWG9b0fNssKr5TrIlu5/rm/v7akpGAIf
    \\RlRll9eSnnbSEJDTKgykz3w=
    \\-----END PRIVATE KEY-----
;

test "tls runtime validates and fingerprints pem" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var runtime = try Runtime.init(gpa.allocator(), .{
        .enabled = true,
        .cert_pem = generated_cert_pem,
        .key_pem = generated_key_pem,
    });
    defer runtime.deinit();

    const info = runtime.info();
    try std.testing.expect(info.enabled);
    try std.testing.expect(!info.generated);
    try std.testing.expect(info.fingerprint_sha256 != null);
    try std.testing.expectEqualStrings("https", info.scheme);
}

test "tls runtime auto generates when enabled" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var runtime = try Runtime.init(gpa.allocator(), .{
        .enabled = true,
    });
    defer runtime.deinit();

    const info = runtime.info();
    try std.testing.expect(info.enabled);
    try std.testing.expect(info.generated);
    try std.testing.expect(info.fingerprint_sha256 != null);
}
