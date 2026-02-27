const std = @import("std");
const x509_self_signed = @import("x509_self_signed.zig");

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
            // Runtime scheme reflects whether TLS material is present and active.
            .scheme = if (has_material) "https" else "http",
        };
    }

    pub fn hasMaterial(self: *const Runtime) bool {
        return self.enabled and self.cert_pem != null and self.key_pem != null;
    }

    fn generateDefaultCertificate(self: *Runtime) !void {
        const pair = try generateEphemeralPemPair(self.allocator);
        errdefer {
            self.allocator.free(pair.cert_pem);
            self.allocator.free(pair.key_pem);
        }

        const fingerprint = try buildSha256Hex(self.allocator, pair.cert_pem);
        errdefer self.allocator.free(fingerprint);

        if (self.cert_pem) |buf| self.allocator.free(buf);
        if (self.key_pem) |buf| self.allocator.free(buf);
        if (self.fingerprint_sha256) |buf| self.allocator.free(buf);

        self.cert_pem = pair.cert_pem;
        self.key_pem = pair.key_pem;
        self.fingerprint_sha256 = fingerprint;
        self.generated = true;
    }
};

const PemPair = x509_self_signed.PemPair;

fn generateEphemeralPemPair(allocator: std.mem.Allocator) !PemPair {
    return x509_self_signed.generateLocalhostPemPair(allocator);
}

fn validatePemPair(cert_pem: []const u8, key_pem: []const u8) !void {
    if (cert_pem.len == 0 or key_pem.len == 0) return error.InvalidTlsPem;

    if (!std.mem.startsWith(u8, cert_pem, "-----BEGIN CERTIFICATE-----")) return error.InvalidTlsCertificatePem;
    if (std.mem.indexOf(u8, cert_pem, "-----END CERTIFICATE-----") == null) return error.InvalidTlsCertificatePem;

    const has_private_key = std.mem.indexOf(u8, key_pem, "-----BEGIN PRIVATE KEY-----") != null and
        std.mem.indexOf(u8, key_pem, "-----END PRIVATE KEY-----") != null;
    const has_rsa_key = std.mem.indexOf(u8, key_pem, "-----BEGIN RSA PRIVATE KEY-----") != null and
        std.mem.indexOf(u8, key_pem, "-----END RSA PRIVATE KEY-----") != null;
    const has_ec_key = std.mem.indexOf(u8, key_pem, "-----BEGIN EC PRIVATE KEY-----") != null and
        std.mem.indexOf(u8, key_pem, "-----END EC PRIVATE KEY-----") != null;
    if (!has_private_key and !has_rsa_key and !has_ec_key) return error.InvalidTlsPrivateKeyPem;
}

fn buildSha256Hex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return allocator.dupe(u8, &hex);
}

test "tls runtime validates and fingerprints user supplied pem" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const cert_pem =
        "-----BEGIN CERTIFICATE-----\n" ++
        "AA==\n" ++
        "-----END CERTIFICATE-----";
    const key_pem =
        "-----BEGIN PRIVATE KEY-----\n" ++
        "AA==\n" ++
        "-----END PRIVATE KEY-----";

    var runtime = try Runtime.init(gpa.allocator(), .{
        .enabled = true,
        .cert_pem = cert_pem,
        .key_pem = key_pem,
    });
    defer runtime.deinit();

    const info = runtime.info();
    try std.testing.expect(info.enabled);
    try std.testing.expect(!info.generated);
    try std.testing.expect(info.fingerprint_sha256 != null);
    try std.testing.expectEqualStrings("https", info.scheme);
}

test "tls runtime auto generates ephemeral certificate at runtime" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var runtime_a = try Runtime.init(gpa.allocator(), .{
        .enabled = true,
    });
    defer runtime_a.deinit();

    var runtime_b = try Runtime.init(gpa.allocator(), .{
        .enabled = true,
    });
    defer runtime_b.deinit();

    const info_a = runtime_a.info();
    try std.testing.expect(info_a.enabled);
    try std.testing.expect(info_a.generated);
    try std.testing.expect(info_a.fingerprint_sha256 != null);

    try std.testing.expect(runtime_a.cert_pem != null);
    try std.testing.expect(runtime_b.cert_pem != null);
    try std.testing.expect(!std.mem.eql(u8, runtime_a.cert_pem.?, runtime_b.cert_pem.?));
}

test "tls runtime errors when cert missing and auto generation disabled" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var runtime = try Runtime.init(gpa.allocator(), .{
        .enabled = true,
        .auto_generate_if_missing = false,
    });
    defer runtime.deinit();

    try std.testing.expectError(error.TlsCertificateMissing, runtime.ensureCertificate());
}
