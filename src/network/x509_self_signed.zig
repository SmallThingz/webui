const std = @import("std");

pub const PemPair = struct {
    cert_pem: []u8,
    key_pem: []u8,
};

const oid_common_name = [_]u8{ 0x55, 0x04, 0x03 };
const oid_ec_public_key = [_]u8{ 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01 };
const oid_prime256v1 = [_]u8{ 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07 };
const oid_ecdsa_sha256 = [_]u8{ 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02 };
const oid_subject_alt_name = [_]u8{ 0x55, 0x1D, 0x11 };

pub fn generateLocalhostPemPair(allocator: std.mem.Allocator) !PemPair {
    const Scheme = std.crypto.sign.ecdsa.EcdsaP256Sha256;
    const key_pair = Scheme.KeyPair.generate();
    const secret_key = key_pair.secret_key.toBytes();
    const public_key_sec1 = key_pair.public_key.toUncompressedSec1();

    const signature_algorithm = try buildSignatureAlgorithm(allocator);
    defer allocator.free(signature_algorithm);

    const name = try buildName(allocator, "localhost");
    defer allocator.free(name);

    const validity = try buildValidity(allocator, "250101000000Z", "351231235959Z");
    defer allocator.free(validity);

    const spki = try buildSubjectPublicKeyInfo(allocator, &public_key_sec1);
    defer allocator.free(spki);

    const extensions = try buildExtensions(allocator);
    defer allocator.free(extensions);

    var tbs_content = std.array_list.Managed(u8).init(allocator);
    defer tbs_content.deinit();

    const version_int = try wrapTag(allocator, 0x02, &.{0x02});
    defer allocator.free(version_int);
    const version_explicit = try wrapTag(allocator, 0xA0, version_int);
    defer allocator.free(version_explicit);
    try tbs_content.appendSlice(version_explicit);

    var serial: [16]u8 = undefined;
    std.crypto.random.bytes(&serial);
    serial[0] &= 0x7F;
    if (serial[0] == 0) serial[0] = 1;
    try appendDerInteger(&tbs_content, &serial);

    try tbs_content.appendSlice(signature_algorithm);
    try tbs_content.appendSlice(name);
    try tbs_content.appendSlice(validity);
    try tbs_content.appendSlice(name);
    try tbs_content.appendSlice(spki);
    try tbs_content.appendSlice(extensions);

    const tbs_certificate = try wrapTag(allocator, 0x30, tbs_content.items);
    defer allocator.free(tbs_certificate);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(tbs_certificate, &digest, .{});
    const signature = try Scheme.KeyPair.signPrehashed(key_pair, digest, null);

    var sig_der_buf: [Scheme.Signature.der_encoded_length_max]u8 = undefined;
    const sig_der = signature.toDer(&sig_der_buf);

    var sig_bit_content = std.array_list.Managed(u8).init(allocator);
    defer sig_bit_content.deinit();
    try sig_bit_content.append(0x00);
    try sig_bit_content.appendSlice(sig_der);
    const sig_bit_string = try wrapTag(allocator, 0x03, sig_bit_content.items);
    defer allocator.free(sig_bit_string);

    var cert_content = std.array_list.Managed(u8).init(allocator);
    defer cert_content.deinit();
    try cert_content.appendSlice(tbs_certificate);
    try cert_content.appendSlice(signature_algorithm);
    try cert_content.appendSlice(sig_bit_string);

    const cert_der = try wrapTag(allocator, 0x30, cert_content.items);
    defer allocator.free(cert_der);

    const ec_private_key_der = try buildEcPrivateKeyDer(allocator, &secret_key, &public_key_sec1);
    defer allocator.free(ec_private_key_der);

    const cert_pem = try pemEncodeBlock(allocator, "CERTIFICATE", cert_der);
    errdefer allocator.free(cert_pem);
    const key_pem = try pemEncodeBlock(allocator, "EC PRIVATE KEY", ec_private_key_der);
    errdefer allocator.free(key_pem);

    return .{
        .cert_pem = cert_pem,
        .key_pem = key_pem,
    };
}

fn buildSignatureAlgorithm(allocator: std.mem.Allocator) ![]u8 {
    var seq = std.array_list.Managed(u8).init(allocator);
    defer seq.deinit();
    try appendDerOid(&seq, &oid_ecdsa_sha256);
    return wrapTag(allocator, 0x30, seq.items);
}

fn buildName(allocator: std.mem.Allocator, common_name: []const u8) ![]u8 {
    var attr = std.array_list.Managed(u8).init(allocator);
    defer attr.deinit();
    try appendDerOid(&attr, &oid_common_name);
    try appendDerUtf8String(&attr, common_name);
    const attr_seq = try wrapTag(allocator, 0x30, attr.items);
    defer allocator.free(attr_seq);

    const attr_set = try wrapTag(allocator, 0x31, attr_seq);
    defer allocator.free(attr_set);

    return wrapTag(allocator, 0x30, attr_set);
}

fn buildValidity(allocator: std.mem.Allocator, not_before: []const u8, not_after: []const u8) ![]u8 {
    var seq = std.array_list.Managed(u8).init(allocator);
    defer seq.deinit();
    try appendDerUtcTime(&seq, not_before);
    try appendDerUtcTime(&seq, not_after);
    return wrapTag(allocator, 0x30, seq.items);
}

fn buildSubjectPublicKeyInfo(allocator: std.mem.Allocator, public_key_sec1: []const u8) ![]u8 {
    var algo = std.array_list.Managed(u8).init(allocator);
    defer algo.deinit();
    try appendDerOid(&algo, &oid_ec_public_key);
    try appendDerOid(&algo, &oid_prime256v1);
    const algo_seq = try wrapTag(allocator, 0x30, algo.items);
    defer allocator.free(algo_seq);

    var bit_content = std.array_list.Managed(u8).init(allocator);
    defer bit_content.deinit();
    try bit_content.append(0x00);
    try bit_content.appendSlice(public_key_sec1);
    const pub_key_bit_string = try wrapTag(allocator, 0x03, bit_content.items);
    defer allocator.free(pub_key_bit_string);

    var spki = std.array_list.Managed(u8).init(allocator);
    defer spki.deinit();
    try spki.appendSlice(algo_seq);
    try spki.appendSlice(pub_key_bit_string);
    return wrapTag(allocator, 0x30, spki.items);
}

fn buildExtensions(allocator: std.mem.Allocator) ![]u8 {
    var general_names_content = std.array_list.Managed(u8).init(allocator);
    defer general_names_content.deinit();
    try appendDerTaggedIA5(&general_names_content, 0x82, "localhost");
    try appendDerTaggedOctets(&general_names_content, 0x87, &[_]u8{ 127, 0, 0, 1 });
    const general_names = try wrapTag(allocator, 0x30, general_names_content.items);
    defer allocator.free(general_names);

    var extension_content = std.array_list.Managed(u8).init(allocator);
    defer extension_content.deinit();
    try appendDerOid(&extension_content, &oid_subject_alt_name);
    try appendDerOctetString(&extension_content, general_names);
    const extension = try wrapTag(allocator, 0x30, extension_content.items);
    defer allocator.free(extension);

    var extensions_seq_content = std.array_list.Managed(u8).init(allocator);
    defer extensions_seq_content.deinit();
    try extensions_seq_content.appendSlice(extension);
    const extensions_seq = try wrapTag(allocator, 0x30, extensions_seq_content.items);
    defer allocator.free(extensions_seq);

    return wrapTag(allocator, 0xA3, extensions_seq);
}

fn buildEcPrivateKeyDer(
    allocator: std.mem.Allocator,
    secret_key: []const u8,
    public_key_sec1: []const u8,
) ![]u8 {
    var seq = std.array_list.Managed(u8).init(allocator);
    defer seq.deinit();

    try appendDerInteger(&seq, &.{0x01});
    try appendDerOctetString(&seq, secret_key);

    var params = std.array_list.Managed(u8).init(allocator);
    defer params.deinit();
    try appendDerOid(&params, &oid_prime256v1);
    const params_explicit = try wrapTag(allocator, 0xA0, params.items);
    defer allocator.free(params_explicit);
    try seq.appendSlice(params_explicit);

    var pub_key_content = std.array_list.Managed(u8).init(allocator);
    defer pub_key_content.deinit();
    try pub_key_content.append(0x00);
    try pub_key_content.appendSlice(public_key_sec1);
    const pub_key_bit_string = try wrapTag(allocator, 0x03, pub_key_content.items);
    defer allocator.free(pub_key_bit_string);

    const pub_key_explicit = try wrapTag(allocator, 0xA1, pub_key_bit_string);
    defer allocator.free(pub_key_explicit);
    try seq.appendSlice(pub_key_explicit);

    return wrapTag(allocator, 0x30, seq.items);
}

fn appendDerOid(list: *std.array_list.Managed(u8), oid_bytes: []const u8) !void {
    try appendDerTagged(list, 0x06, oid_bytes);
}

fn appendDerUtf8String(list: *std.array_list.Managed(u8), value: []const u8) !void {
    try appendDerTagged(list, 0x0C, value);
}

fn appendDerUtcTime(list: *std.array_list.Managed(u8), value: []const u8) !void {
    try appendDerTagged(list, 0x17, value);
}

fn appendDerOctetString(list: *std.array_list.Managed(u8), value: []const u8) !void {
    try appendDerTagged(list, 0x04, value);
}

fn appendDerTaggedIA5(list: *std.array_list.Managed(u8), tag: u8, value: []const u8) !void {
    try appendDerTagged(list, tag, value);
}

fn appendDerTaggedOctets(list: *std.array_list.Managed(u8), tag: u8, value: []const u8) !void {
    try appendDerTagged(list, tag, value);
}

fn appendDerInteger(list: *std.array_list.Managed(u8), integer_bytes: []const u8) !void {
    var trimmed = std.mem.trimLeft(u8, integer_bytes, "\x00");
    if (trimmed.len == 0) trimmed = &.{0};

    var value = std.array_list.Managed(u8).init(list.allocator);
    defer value.deinit();
    if ((trimmed[0] & 0x80) != 0) try value.append(0);
    try value.appendSlice(trimmed);

    try appendDerTagged(list, 0x02, value.items);
}

fn appendDerTagged(list: *std.array_list.Managed(u8), tag: u8, value: []const u8) !void {
    try list.append(tag);
    try appendDerLength(list, value.len);
    try list.appendSlice(value);
}

fn appendDerLength(list: *std.array_list.Managed(u8), len: usize) !void {
    if (len < 128) {
        try list.append(@intCast(len));
        return;
    }

    var len_bytes: [8]u8 = undefined;
    var i: usize = len_bytes.len;
    var value = len;
    while (value > 0) {
        i -= 1;
        len_bytes[i] = @intCast(value & 0xFF);
        value >>= 8;
    }
    const count = len_bytes.len - i;
    try list.append(0x80 | @as(u8, @intCast(count)));
    try list.appendSlice(len_bytes[i..]);
}

fn wrapTag(allocator: std.mem.Allocator, tag: u8, content: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    try out.append(tag);
    try appendDerLength(&out, content.len);
    try out.appendSlice(content);

    return out.toOwnedSlice();
}

fn pemEncodeBlock(allocator: std.mem.Allocator, label: []const u8, raw: []const u8) ![]u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(raw.len);
    const encoded = try allocator.alloc(u8, encoded_len);
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, raw);

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    try out.writer().print("-----BEGIN {s}-----\n", .{label});
    var offset: usize = 0;
    while (offset < encoded.len) : (offset += 64) {
        const end = @min(offset + 64, encoded.len);
        try out.appendSlice(encoded[offset..end]);
        try out.append('\n');
    }
    try out.writer().print("-----END {s}-----", .{label});

    return out.toOwnedSlice();
}

test "generateLocalhostPemPair emits parseable PEM envelope" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const pair = try generateLocalhostPemPair(gpa.allocator());
    defer {
        gpa.allocator().free(pair.cert_pem);
        gpa.allocator().free(pair.key_pem);
    }

    try std.testing.expect(std.mem.startsWith(u8, pair.cert_pem, "-----BEGIN CERTIFICATE-----"));
    try std.testing.expect(std.mem.startsWith(u8, pair.key_pem, "-----BEGIN EC PRIVATE KEY-----"));
}
