const types = @import("api_types.zig");

pub fn order(policy: types.LaunchPolicy) [3]?types.LaunchSurface {
    var out: [3]?types.LaunchSurface = .{ null, null, null };
    var write_idx: usize = 0;
    const input = [_]?types.LaunchSurface{ policy.first, policy.second, policy.third };
    for (input) |candidate| {
        if (candidate == null) continue;

        var duplicate = false;
        for (out) |existing| {
            if (existing != null and existing.? == candidate.?) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        out[write_idx] = candidate.?;
        write_idx += 1;
        if (write_idx >= out.len) break;
    }

    if (out[0] == null) out[0] = .web_url;
    return out;
}

pub fn contains(policy: types.LaunchPolicy, surface: types.LaunchSurface) bool {
    const ordered = order(policy);
    for (ordered) |candidate| {
        if (candidate == null) continue;
        if (candidate.? == surface) return true;
    }
    return false;
}

pub fn nextAfter(policy: types.LaunchPolicy, current: types.LaunchSurface) ?types.LaunchSurface {
    const ordered = order(policy);
    var found = false;
    for (ordered) |candidate| {
        if (candidate == null) continue;
        if (!found) {
            if (candidate.? == current) found = true;
            continue;
        }
        return candidate.?;
    }
    return null;
}
