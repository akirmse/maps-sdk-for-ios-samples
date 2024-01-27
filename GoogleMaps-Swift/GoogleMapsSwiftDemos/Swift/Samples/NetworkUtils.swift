//
//  NetworkUtils.swift
//  Peakbagger
//
//  Created by Andrew KIRMSE on 7/15/15.
//  Copyright (c) 2015 Mountainside. All rights reserved.
//

import Foundation
import SystemConfiguration

class NetworkUtils {
    static let USER_AGENT_STRING = "Peakbagger/1.0 (iOS)"
    static let TIMEOUT_SEC = 10.0
    private static let DEFAULT_HEADERS = ["Content-Type" : "application/x-www-form-urlencoded"]
    
    // Prevent instantiation
    private init() {
    }

    // Fetch the given unencoded URL asynchronously, and invoke the callback with the contents as a byte sequence.
    // Returns nil on an error.
    class func fetchUrlToBytes(_ url: String, callback: @escaping (Data?) -> ()) {
        fetchUrlToBytesWithHeaders(url, headers: nil, callback: callback)
    }
    
    class func fetchUrlToBytesWithHeaders(_ url: String, headers: [String: String]?, callback: @escaping (Data?) -> ()) {
        if let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) {
            fetchEncodedUrlToBytes(encodedUrl, headers: headers) { data in
                callback(data)
            }
        } else {
            callback(nil)
        }
    }
    
    // Fetch the given encoded URL asynchronously, and invokes the callback on an unknown thread
    // with the contents as a byte sequence. Calls callback with nil on an error.
    class func fetchEncodedUrlToBytes(_ encodedUrl: String, headers: [String: String]?, callback: @escaping (Data?) -> ()) {
        guard let url = URL(string: encodedUrl) else {
            callback(nil)
            return
        }

        var request = URLRequest(url: url)
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        request.timeoutInterval = Self.TIMEOUT_SEC

        URLSession.shared.dataTask(with: request) { data, response, error in
            var retval = data
            if let error = error {
                // log.warning("Couldn't fetch url \(encodedUrl), error = \(error)")
                retval = nil
            } else {
                // An HTTP 500 error doesn't count as "error", but instead sets the status code
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode >= 400 && httpResponse.statusCode < 600 {
                    retval = nil
                }
            }
            
            callback(retval)
        }.resume()
    }
    
    class func fetchUrlToString(_ url: String, callback: @escaping (String?) -> ()) {
        fetchUrlToBytes(url) { data in
            if let data = data {
                callback(String(data: data, encoding: .utf8))
            } else {
                callback(nil)
            }
        }
    }
}
