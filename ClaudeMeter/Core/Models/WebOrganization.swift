//
//  WebOrganization.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// An organization as reported by claude.ai, used to resolve the organization id the usage
/// endpoint needs so the user never has to copy a UUID out of a browser URL.
///
/// The decoding here is deliberately tolerant. This is an undocumented endpoint: it may hand
/// back a bare array or wrap it, and may name the identifier `uuid` or `id`. Accepting the
/// plausible shapes costs little and avoids the whole feature breaking on a key rename.
struct WebOrganization: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
    let capabilities: [String]

    private enum CodingKeys: String, CodingKey {
        case uuid, id, name, displayName = "display_name", capabilities
    }

    init(id: String, name: String, capabilities: [String] = []) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let identifier = try container.decodeIfPresent(String.self, forKey: .uuid)
            ?? container.decodeIfPresent(String.self, forKey: .id) else {
            throw DecodingError.dataCorruptedError(
                forKey: .uuid, in: container,
                debugDescription: "Organization has neither `uuid` nor `id`"
            )
        }

        id = identifier
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
            ?? identifier
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }
}

/// Wrapper for the case where the endpoint nests the list instead of returning a bare array.
struct WebOrganizationList: Decodable {
    let organizations: [WebOrganization]

    private enum CodingKeys: String, CodingKey {
        case organizations, data, results
    }

    init(from decoder: Decoder) throws {
        if let bare = try? [WebOrganization](from: decoder) {
            organizations = bare
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        organizations = try container.decodeIfPresent([WebOrganization].self, forKey: .organizations)
            ?? container.decodeIfPresent([WebOrganization].self, forKey: .data)
            ?? container.decodeIfPresent([WebOrganization].self, forKey: .results)
            ?? []
    }
}

extension Array where Element == WebOrganization {
    /// Pick the organization whose usage is worth showing: prefer one that can actually chat,
    /// otherwise just take the first.
    var preferredForUsage: WebOrganization? {
        first { $0.capabilities.contains("chat") } ?? first
    }
}
